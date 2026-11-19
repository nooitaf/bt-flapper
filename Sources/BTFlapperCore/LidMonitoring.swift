import Foundation
import IOKit
import IOKit.pwr_mgt
import os

public enum LidEvent {
    case lidClosed
    case lidOpened
    case systemWillSleep(completion: () -> Void)
    case systemDidWake(lidClosed: Bool)
}

public protocol LidMonitoring: AnyObject {
    var isLidClosed: Bool { get }
    func start(handler: @escaping (LidEvent) -> Void)
    func stop()
}

/// Observes MacBook lid (clamshell) state via `IOPMrootDomain`'s `AppleClamshellState`
/// and coordinates briefly with system sleep so Bluetooth disconnects finish before suspend.
public final class SystemLidMonitor: LidMonitoring {
    // IOKit power management message constants (from <IOKit/IOMessage.h>)
    private static let msgCanSystemSleep: UInt32 = 0xe000_0270
    private static let msgSystemWillSleep: UInt32 = 0xe000_0280
    private static let msgSystemHasPoweredOn: UInt32 = 0xe000_0300

    private let logger = Logger(subsystem: "com.github.nooitaf.bt-flapper", category: "lid")
    private let queue = DispatchQueue(label: "com.github.nooitaf.bt-flapper.lid-monitor")

    private var handler: ((LidEvent) -> Void)?
    private var lastKnownLidClosed: Bool = false
    private var isStarted: Bool = false

    // Clamshell interest notification resources
    private var rootDomainService: io_service_t = 0
    private var clamshellNotifyPort: IONotificationPortRef?
    private var clamshellNotifier: io_object_t = 0

    // System power notification resources
    private var powerRootPort: io_connect_t = 0
    private var powerNotifyPort: IONotificationPortRef?
    private var powerNotifier: io_object_t = 0

    public init() {}

    deinit {
        stop()
    }

    public var isLidClosed: Bool {
        Self.readClamshellState() ?? lastKnownLidClosed
    }

    public func start(handler: @escaping (LidEvent) -> Void) {
        queue.sync {
            guard !isStarted else { return }
            self.handler = handler
            self.lastKnownLidClosed = Self.readClamshellState() ?? false
            self.isStarted = true

            registerClamshellNotifications()
            registerPowerNotifications()
            logger.info("Lid monitor started (initial lidClosed=\(self.lastKnownLidClosed))")
        }
    }

    public func stop() {
        queue.sync {
            guard isStarted else { return }
            isStarted = false
            handler = nil

            if clamshellNotifier != 0 {
                IOObjectRelease(clamshellNotifier)
                clamshellNotifier = 0
            }
            if let port = clamshellNotifyPort {
                IONotificationPortDestroy(port)
                clamshellNotifyPort = nil
            }
            if rootDomainService != 0 {
                IOObjectRelease(rootDomainService)
                rootDomainService = 0
            }

            if powerNotifier != 0 {
                IODeregisterForSystemPower(&powerNotifier)
                powerNotifier = 0
            }
            if let port = powerNotifyPort {
                IONotificationPortDestroy(port)
                powerNotifyPort = nil
            }
            if powerRootPort != 0 {
                IOServiceClose(powerRootPort)
                powerRootPort = 0
            }
        }
    }

    private func registerClamshellNotifications() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else {
            logger.error("Failed to find IOPMrootDomain service")
            return
        }
        rootDomainService = service

        guard let port = IONotificationPortCreate(kIOMainPortDefault) else {
            logger.error("Failed to create IONotificationPort for clamshell state")
            return
        }
        clamshellNotifyPort = port
        IONotificationPortSetDispatchQueue(port, queue)

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let result = IOServiceAddInterestNotification(
            port,
            service,
            kIOGeneralInterest,
            { refcon, _, _, _ in
                guard let refcon else { return }
                let monitor = Unmanaged<SystemLidMonitor>.fromOpaque(refcon).takeUnretainedValue()
                monitor.handleClamshellNotification()
            },
            refcon,
            &clamshellNotifier
        )

        if result != kIOReturnSuccess {
            logger.error("Failed to register clamshell interest notification: \(result)")
        }
    }

    private func registerPowerNotifications() {
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        var notifyPort: IONotificationPortRef?
        let rootPort = IORegisterForSystemPower(
            refcon,
            &notifyPort,
            { refcon, _, messageType, messageArgument in
                guard let refcon else { return }
                let monitor = Unmanaged<SystemLidMonitor>.fromOpaque(refcon).takeUnretainedValue()
                monitor.handlePowerMessage(messageType: messageType, messageArgument: messageArgument)
            },
            &powerNotifier
        )

        guard rootPort != 0, let notifyPort else {
            logger.error("Failed to register for system power notifications")
            return
        }

        powerRootPort = rootPort
        powerNotifyPort = notifyPort
        IONotificationPortSetDispatchQueue(notifyPort, queue)
    }

    private func handleClamshellNotification() {
        guard isStarted, let closed = Self.readClamshellState() else { return }
        guard closed != lastKnownLidClosed else { return }

        lastKnownLidClosed = closed
        logger.info("Lid state changed: closed=\(closed)")
        handler?(closed ? .lidClosed : .lidOpened)
    }

    private func handlePowerMessage(messageType: UInt32, messageArgument: UnsafeMutableRawPointer?) {
        guard isStarted else { return }
        let notificationID = Int(bitPattern: messageArgument)

        switch messageType {
        case Self.msgCanSystemSleep:
            IOAllowPowerChange(powerRootPort, notificationID)

        case Self.msgSystemWillSleep:
            let rootPort = powerRootPort
            let lock = NSLock()
            var allowed = false

            let allowOnce: () -> Void = {
                lock.lock()
                defer { lock.unlock() }
                guard !allowed else { return }
                allowed = true
                IOAllowPowerChange(rootPort, notificationID)
            }

            // Safety net: never delay macOS sleep for more than 2.5 seconds.
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 2.5) {
                allowOnce()
            }

            if let handler {
                handler(.systemWillSleep(completion: allowOnce))
            } else {
                allowOnce()
            }

        case Self.msgSystemHasPoweredOn:
            let closed = Self.readClamshellState() ?? lastKnownLidClosed
            lastKnownLidClosed = closed
            handler?(.systemDidWake(lidClosed: closed))

        default:
            break
        }
    }

    private static func readClamshellState() -> Bool? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        guard let property = IORegistryEntryCreateCFProperty(
            service,
            "AppleClamshellState" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() else {
            return nil
        }

        return property as? Bool
    }
}
