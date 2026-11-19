import Foundation
import os

public final class FlapperController {
    private static let enabledDefaultsKey = "bt-flapper.enabled"

    private let logger = Logger(subsystem: "com.github.nooitaf.bt-flapper", category: "controller")
    private let bluetoothManager: BluetoothManaging
    private let lidMonitor: LidMonitoring
    private let userDefaults: UserDefaults
    private let reconnectDelay: TimeInterval
    private let sleepWaitTimeout: TimeInterval

    private let stateQueue = DispatchQueue(label: "com.github.nooitaf.bt-flapper.state")
    private let bluetoothQueue = DispatchQueue(
        label: "com.github.nooitaf.bt-flapper.bluetooth-ops",
        qos: .userInitiated,
        attributes: .concurrent
    )

    private var rememberedAddresses: [String] = []
    private var pendingReconnectWorkItem: DispatchWorkItem?
    private var activeDisconnectGroup: DispatchGroup?

    public var onEnabledChanged: ((Bool) -> Void)?

    public var isEnabled: Bool {
        get {
            stateQueue.sync {
                if userDefaults.object(forKey: Self.enabledDefaultsKey) == nil {
                    return true
                }
                return userDefaults.bool(forKey: Self.enabledDefaultsKey)
            }
        }
        set {
            stateQueue.sync {
                userDefaults.set(newValue, forKey: Self.enabledDefaultsKey)
                if !newValue {
                    pendingReconnectWorkItem?.cancel()
                    pendingReconnectWorkItem = nil
                    rememberedAddresses.removeAll()
                }
            }
            logger.info("bt-flapper enabled=\(newValue)")
            onEnabledChanged?(newValue)
        }
    }

    public init(
        bluetoothManager: BluetoothManaging = SystemBluetoothManager(),
        lidMonitor: LidMonitoring = SystemLidMonitor(),
        userDefaults: UserDefaults = .standard,
        reconnectDelay: TimeInterval = 1.5,
        sleepWaitTimeout: TimeInterval = 2.0
    ) {
        self.bluetoothManager = bluetoothManager
        self.lidMonitor = lidMonitor
        self.userDefaults = userDefaults
        self.reconnectDelay = reconnectDelay
        self.sleepWaitTimeout = sleepWaitTimeout
    }

    public func requestBluetoothPermission(completion: (() -> Void)? = nil) {
        bluetoothQueue.async { [weak self] in
            self?.bluetoothManager.requestPermission()
            completion?()
        }
    }

    public func start() {
        lidMonitor.start { [weak self] event in
            self?.handle(event)
        }
    }

    public func stop() {
        lidMonitor.stop()
        stateQueue.sync {
            pendingReconnectWorkItem?.cancel()
            pendingReconnectWorkItem = nil
        }
    }

    private func handle(_ event: LidEvent) {
        switch event {
        case .lidClosed:
            handleLidClosed()
        case .lidOpened:
            handleLidOpened()
        case .systemWillSleep(let completion):
            handleSystemWillSleep(completion: completion)
        case .systemDidWake(let lidClosed):
            handleSystemDidWake(lidClosed: lidClosed)
        }
    }

    private func handleLidClosed() {
        stateQueue.async { [weak self] in
            guard let self else { return }
            self.pendingReconnectWorkItem?.cancel()
            self.pendingReconnectWorkItem = nil

            guard self.readEnabledLocked() else { return }
            _ = self.snapshotAndDisconnectLocked(preserveExisting: false)
        }
    }

    private func handleSystemWillSleep(completion: @escaping () -> Void) {
        stateQueue.async { [weak self] in
            guard let self else {
                completion()
                return
            }

            self.pendingReconnectWorkItem?.cancel()
            self.pendingReconnectWorkItem = nil

            guard self.readEnabledLocked(), self.lidMonitor.isLidClosed else {
                completion()
                return
            }

            let group: DispatchGroup
            if let existingGroup = self.activeDisconnectGroup {
                group = existingGroup
            } else {
                group = self.snapshotAndDisconnectLocked(preserveExisting: true)
            }

            let timeout = self.sleepWaitTimeout
            self.bluetoothQueue.async {
                _ = group.wait(timeout: .now() + timeout)
                completion()
            }
        }
    }

    private func handleSystemDidWake(lidClosed: Bool) {
        stateQueue.async { [weak self] in
            guard let self else { return }
            guard self.readEnabledLocked(), lidClosed else { return }

            // Dark wake while lid is still closed: make sure nothing hijacked a device.
            _ = self.snapshotAndDisconnectLocked(preserveExisting: true)
        }
    }

    private func handleLidOpened() {
        stateQueue.async { [weak self] in
            guard let self else { return }
            self.pendingReconnectWorkItem?.cancel()
            self.pendingReconnectWorkItem = nil

            guard self.readEnabledLocked() else { return }

            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.pendingReconnectWorkItem = nil

                guard self.readEnabledLocked(), !self.lidMonitor.isLidClosed else {
                    return
                }

                let addressesToReconnect = self.rememberedAddresses
                self.rememberedAddresses.removeAll()

                guard !addressesToReconnect.isEmpty else { return }
                self.logger.info("Attempting to reconnect \(addressesToReconnect.count) device(s)")

                let currentlyConnected = Set(
                    self.bluetoothManager.connectedDevices().map { $0.address.lowercased() }
                )

                for address in addressesToReconnect {
                    if currentlyConnected.contains(address.lowercased()) {
                        continue
                    }
                    self.bluetoothQueue.async { [weak self] in
                        self?.bluetoothManager.connect(address: address)
                    }
                }
            }

            self.pendingReconnectWorkItem = workItem
            if self.reconnectDelay <= 0 {
                self.stateQueue.async(execute: workItem)
            } else {
                self.stateQueue.asyncAfter(deadline: .now() + self.reconnectDelay, execute: workItem)
            }
        }
    }

    private func snapshotAndDisconnectLocked(preserveExisting: Bool) -> DispatchGroup {
        let connected = bluetoothManager.connectedDevices()
        let newAddresses = connected.map(\.address)

        if preserveExisting {
            let existingLower = Set(rememberedAddresses.map { $0.lowercased() })
            for address in newAddresses where !existingLower.contains(address.lowercased()) {
                rememberedAddresses.append(address)
            }
        } else {
            rememberedAddresses = newAddresses
        }

        let group = DispatchGroup()
        guard !newAddresses.isEmpty else {
            return group
        }

        logger.info("Disconnecting \(newAddresses.count) Bluetooth device(s)")
        activeDisconnectGroup = group

        for address in newAddresses {
            group.enter()
            bluetoothQueue.async { [weak self] in
                self?.bluetoothManager.disconnect(address: address)
                group.leave()
            }
        }

        group.notify(queue: stateQueue) { [weak self] in
            if self?.activeDisconnectGroup === group {
                self?.activeDisconnectGroup = nil
            }
        }

        return group
    }

    private func readEnabledLocked() -> Bool {
        if userDefaults.object(forKey: Self.enabledDefaultsKey) == nil {
            return true
        }
        return userDefaults.bool(forKey: Self.enabledDefaultsKey)
    }
}
