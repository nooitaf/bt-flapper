import Foundation
import BTFlapperCore

private final class MockBluetoothManager: BluetoothManaging {
    private let lock = NSLock()
    private var connected: [BluetoothDeviceInfo]
    private var disconnected: [String] = []
    private var connectAttemptsList: [String] = []
    var onDisconnect: ((String) -> Void)?
    var onConnect: ((String) -> Void)?

    init(connected: [BluetoothDeviceInfo] = []) {
        self.connected = connected
    }

    var disconnectedAddresses: [String] {
        lock.lock()
        defer { lock.unlock() }
        return disconnected
    }

    var connectedAttempts: [String] {
        lock.lock()
        defer { lock.unlock() }
        return connectAttemptsList
    }

    func setConnected(_ devices: [BluetoothDeviceInfo]) {
        lock.lock()
        connected = devices
        lock.unlock()
    }

    func requestPermission() {}

    func connectedDevices() -> [BluetoothDeviceInfo] {
        lock.lock()
        defer { lock.unlock() }
        return connected
    }

    @discardableResult
    func disconnect(address: String) -> Bool {
        lock.lock()
        disconnected.append(address)
        connected.removeAll { $0.address.caseInsensitiveCompare(address) == .orderedSame }
        let callback = onDisconnect
        lock.unlock()
        callback?(address)
        return true
    }

    @discardableResult
    func connect(address: String) -> Bool {
        lock.lock()
        connectAttemptsList.append(address)
        let callback = onConnect
        lock.unlock()
        callback?(address)
        return true
    }
}

private final class MockLidMonitor: LidMonitoring {
    var isLidClosed: Bool = false
    private var handler: ((LidEvent) -> Void)?

    func start(handler: @escaping (LidEvent) -> Void) {
        self.handler = handler
    }

    func stop() {
        handler = nil
    }

    func emit(_ event: LidEvent) {
        switch event {
        case .lidClosed:
            isLidClosed = true
        case .lidOpened:
            isLidClosed = false
        case .systemDidWake(let lidClosed):
            isLidClosed = lidClosed
        case .systemWillSleep:
            break
        }
        handler?(event)
    }
}

private var failures = 0

private func expect(_ condition: @autoclosure () -> Bool, _ message: String, line: UInt = #line) {
    if !condition() {
        failures += 1
        fputs("FAIL (line \(line)): \(message)\n", stderr)
    }
}

private func makeDefaults() -> (UserDefaults, String) {
    let suite = "com.github.nooitaf.bt-flapper.tests.\(UUID().uuidString)"
    return (UserDefaults(suiteName: suite)!, suite)
}

private func runTest(_ name: String, _ body: () -> Void) {
    let before = failures
    body()
    if failures == before {
        print("PASS: \(name)")
    }
}

runTest("Lid close disconnects connected devices and lid open reconnects them once") {
    let (defaults, suite) = makeDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let headphones = BluetoothDeviceInfo(address: "aa-bb-cc-dd-ee-01", name: "Headphones")
    let speaker = BluetoothDeviceInfo(address: "aa-bb-cc-dd-ee-02", name: "Speaker")
    let bt = MockBluetoothManager(connected: [headphones, speaker])
    let lid = MockLidMonitor()

    let controller = FlapperController(
        bluetoothManager: bt,
        lidMonitor: lid,
        userDefaults: defaults,
        reconnectDelay: 0
    )
    controller.start()

    let disconnectGroup = DispatchGroup()
    disconnectGroup.enter()
    disconnectGroup.enter()
    bt.onDisconnect = { _ in disconnectGroup.leave() }

    lid.emit(.lidClosed)
    expect(disconnectGroup.wait(timeout: .now() + 2.0) == .success, "Expected disconnect to finish")
    expect(Set(bt.disconnectedAddresses) == Set([headphones.address, speaker.address]), "Expected both devices disconnected")

    let reconnectGroup = DispatchGroup()
    reconnectGroup.enter()
    reconnectGroup.enter()
    bt.onConnect = { _ in reconnectGroup.leave() }

    lid.emit(.lidOpened)
    expect(reconnectGroup.wait(timeout: .now() + 2.0) == .success, "Expected reconnect to finish")
    expect(Set(bt.connectedAttempts) == Set([headphones.address, speaker.address]), "Expected both devices reconnected")

    bt.onConnect = { _ in expect(false, "Should not reconnect a second time") }
    lid.emit(.lidOpened)
    Thread.sleep(forTimeInterval: 0.05)
}

runTest("Lid open skips devices that are already connected") {
    let (defaults, suite) = makeDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let headphones = BluetoothDeviceInfo(address: "aa-bb-cc-dd-ee-01", name: "Headphones")
    let mouse = BluetoothDeviceInfo(address: "aa-bb-cc-dd-ee-02", name: "Mouse")
    let bt = MockBluetoothManager(connected: [headphones, mouse])
    let lid = MockLidMonitor()

    let controller = FlapperController(
        bluetoothManager: bt,
        lidMonitor: lid,
        userDefaults: defaults,
        reconnectDelay: 0
    )
    controller.start()

    let disconnectGroup = DispatchGroup()
    disconnectGroup.enter()
    disconnectGroup.enter()
    bt.onDisconnect = { _ in disconnectGroup.leave() }
    lid.emit(.lidClosed)
    expect(disconnectGroup.wait(timeout: .now() + 2.0) == .success, "Expected disconnect to finish")

    bt.setConnected([mouse])

    let reconnectSem = DispatchSemaphore(value: 0)
    bt.onConnect = { address in
        expect(address == headphones.address, "Expected only headphones to reconnect")
        reconnectSem.signal()
    }

    lid.emit(.lidOpened)
    expect(reconnectSem.wait(timeout: .now() + 2.0) == .success, "Expected headphones reconnect")
    expect(bt.connectedAttempts == [headphones.address], "Expected only headphones in attempts")
}

runTest("Disabled state ignores lid events") {
    let (defaults, suite) = makeDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let headphones = BluetoothDeviceInfo(address: "aa-bb-cc-dd-ee-01", name: "Headphones")
    let bt = MockBluetoothManager(connected: [headphones])
    let lid = MockLidMonitor()

    let controller = FlapperController(
        bluetoothManager: bt,
        lidMonitor: lid,
        userDefaults: defaults,
        reconnectDelay: 0
    )
    controller.isEnabled = false
    controller.start()

    bt.onDisconnect = { _ in expect(false, "Should not disconnect when disabled") }
    bt.onConnect = { _ in expect(false, "Should not connect when disabled") }

    lid.emit(.lidClosed)
    lid.emit(.lidOpened)
    Thread.sleep(forTimeInterval: 0.05)

    expect(bt.disconnectedAddresses.isEmpty, "Expected no disconnects")
    expect(bt.connectedAttempts.isEmpty, "Expected no connects")
}

runTest("Dark wake while lid is closed disconnects again and preserves remembered devices") {
    let (defaults, suite) = makeDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let headphones = BluetoothDeviceInfo(address: "aa-bb-cc-dd-ee-01", name: "Headphones")
    let bt = MockBluetoothManager(connected: [headphones])
    let lid = MockLidMonitor()

    let controller = FlapperController(
        bluetoothManager: bt,
        lidMonitor: lid,
        userDefaults: defaults,
        reconnectDelay: 0
    )
    controller.start()

    let initialDisconnect = DispatchSemaphore(value: 0)
    bt.onDisconnect = { _ in initialDisconnect.signal() }
    lid.emit(.lidClosed)
    expect(initialDisconnect.wait(timeout: .now() + 2.0) == .success, "Expected initial disconnect")

    bt.setConnected([headphones])
    let darkWakeDisconnect = DispatchSemaphore(value: 0)
    bt.onDisconnect = { _ in darkWakeDisconnect.signal() }
    bt.onConnect = { _ in expect(false, "Should not reconnect while lid is closed") }

    lid.emit(.systemDidWake(lidClosed: true))
    expect(darkWakeDisconnect.wait(timeout: .now() + 2.0) == .success, "Expected dark wake disconnect")

    let reconnectSem = DispatchSemaphore(value: 0)
    bt.onConnect = { _ in reconnectSem.signal() }
    lid.emit(.lidOpened)
    expect(reconnectSem.wait(timeout: .now() + 2.0) == .success, "Expected reconnect on lid open")
    expect(bt.connectedAttempts == [headphones.address], "Expected headphones reconnected")
}

runTest("System will sleep waits for disconnect completion before allowing sleep") {
    let (defaults, suite) = makeDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let headphones = BluetoothDeviceInfo(address: "aa-bb-cc-dd-ee-01", name: "Headphones")
    let bt = MockBluetoothManager(connected: [headphones])
    let lid = MockLidMonitor()

    let controller = FlapperController(
        bluetoothManager: bt,
        lidMonitor: lid,
        userDefaults: defaults,
        reconnectDelay: 0
    )
    controller.start()

    lid.isLidClosed = true
    let sleepAllowed = DispatchSemaphore(value: 0)

    lid.emit(.systemWillSleep(completion: {
        sleepAllowed.signal()
    }))

    expect(sleepAllowed.wait(timeout: .now() + 2.0) == .success, "Expected sleep completion")
    expect(bt.disconnectedAddresses == [headphones.address], "Expected disconnect before sleep")
}

if failures > 0 {
    fputs("\(failures) test assertion(s) failed.\n", stderr)
    exit(1)
}
print("All tests passed!")
