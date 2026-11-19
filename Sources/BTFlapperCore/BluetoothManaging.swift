import Foundation
import IOBluetooth
import os

public struct BluetoothDeviceInfo: Equatable, Hashable, Sendable {
    public let address: String
    public let name: String

    public init(address: String, name: String) {
        self.address = address
        self.name = name
    }
}

public protocol BluetoothManaging: AnyObject {
    func requestPermission()
    func connectedDevices() -> [BluetoothDeviceInfo]
    @discardableResult func disconnect(address: String) -> Bool
    @discardableResult func connect(address: String) -> Bool
}

public final class SystemBluetoothManager: BluetoothManaging {
    private let logger = Logger(subsystem: "com.github.nooitaf.bt-flapper", category: "bluetooth")

    public init() {}

    public func requestPermission() {
        _ = IOBluetoothDevice.pairedDevices()
    }

    public func connectedDevices() -> [BluetoothDeviceInfo] {
        guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            return []
        }

        return paired.compactMap { device in
            guard device.isConnected(),
                  let address = device.addressString,
                  !address.isEmpty else {
                return nil
            }
            let name = device.name ?? address
            return BluetoothDeviceInfo(address: address, name: name)
        }
    }

    @discardableResult
    public func disconnect(address: String) -> Bool {
        guard let device = findDevice(address: address) else {
            logger.warning("Device not found for disconnect: \(address, privacy: .public)")
            return false
        }

        guard device.isConnected() else {
            return true
        }

        let name = device.name ?? address
        let status = device.closeConnection()
        if status == kIOReturnSuccess {
            logger.info("Disconnected \(name, privacy: .public) (\(address, privacy: .public))")
            return true
        } else {
            logger.warning("Failed to disconnect \(name, privacy: .public) (\(address, privacy: .public)): \(status)")
            return false
        }
    }

    @discardableResult
    public func connect(address: String) -> Bool {
        guard let device = findDevice(address: address) else {
            logger.warning("Device not found for connect: \(address, privacy: .public)")
            return false
        }

        guard !device.isConnected() else {
            return true
        }

        let name = device.name ?? address
        let status = device.openConnection()
        if status == kIOReturnSuccess {
            logger.info("Reconnected \(name, privacy: .public) (\(address, privacy: .public))")
            return true
        } else {
            logger.info("Could not reconnect \(name, privacy: .public) (\(address, privacy: .public)): \(status)")
            return false
        }
    }

    private func findDevice(address: String) -> IOBluetoothDevice? {
        if let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice],
           let match = paired.first(where: { $0.addressString?.caseInsensitiveCompare(address) == .orderedSame }) {
            return match
        }
        return IOBluetoothDevice(addressString: address)
    }
}
