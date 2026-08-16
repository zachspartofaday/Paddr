import Foundation
import Synchronization
#if canImport(IOKit)
import IOKit
import IOKit.hid
import IOKit.hidsystem
#endif

public struct TritonInterfaceSummary: Sendable {
    public let interfaceNumber: Int?
    public let usagePage: Int?
    public let usage: Int?
    public let maximumInputReportSize: Int

    public init(interfaceNumber: Int?, usagePage: Int?, usage: Int?, maximumInputReportSize: Int) {
        self.interfaceNumber = interfaceNumber
        self.usagePage = usagePage
        self.usage = usage
        self.maximumInputReportSize = maximumInputReportSize
    }
}

public struct TritonDeviceSummary: Sendable {
    public let productID: UInt16
    public let interfaces: [TritonInterfaceSummary]

    public init(productID: UInt16, interfaces: [TritonInterfaceSummary]) {
        self.productID = productID
        self.interfaces = interfaces
    }

    public var description: String {
        let interfaceText = interfaces
            .map { $0.interfaceNumber.map(String.init) ?? "?" }
            .joined(separator: ",")
        let reportText = Set(interfaces.map(\.maximumInputReportSize))
            .sorted()
            .map(String.init)
            .joined(separator: ",")
        return String(format: "Valve 0x28DE:0x%04X interfaces=%@ inputReport=%@", productID, interfaceText, reportText)
    }
}

#if canImport(IOKit)
private final class HIDCallbackState: Sendable {
    private struct State: ~Copyable {
        var reports: [TrackpadHIDReport] = []
        var deviceRemoved = false
    }

    private let state = Mutex(State())

    func append(slot: Int, bytes: [UInt8]) {
        state.withLock { state in
            guard !state.deviceRemoved else { return }
            state.reports.append(TrackpadHIDReport(
                slot: slot,
                bytes: bytes,
                timestampNanoseconds: DispatchTime.now().uptimeNanoseconds
            ))
        }
    }

    func drain() -> [TrackpadHIDReport] {
        state.withLock { state in
            guard !state.deviceRemoved else { return [] }
            let result = state.reports
            state.reports.removeAll(keepingCapacity: true)
            return result
        }
    }

    func markRemoved() {
        state.withLock { state in
            state.deviceRemoved = true
            state.reports.removeAll(keepingCapacity: false)
        }
    }

    var isRemoved: Bool {
        state.withLock { $0.deviceRemoved }
    }
}
#endif

public enum TrackpadStreamTermination: Equatable, Sendable {
    case stopped
    case deviceRemoved
}

/// One drained HID input report tagged with the controller slot (opened-interface index)
/// it arrived on, so slot identity survives the multi-interface fan-in.
public struct TrackpadHIDReport: Equatable, Sendable {
    public let slot: Int
    public let bytes: [UInt8]
    public let timestampNanoseconds: UInt64

    public init(slot: Int, bytes: [UInt8], timestampNanoseconds: UInt64) {
        self.slot = slot
        self.bytes = bytes
        self.timestampNanoseconds = timestampNanoseconds
    }
}

public protocol TrackpadHIDStreaming {
    var summaryDescription: String { get }
    func stream(
        shouldContinue: () -> Bool,
        onWake: () throws -> Void,
        onReport: (TrackpadHIDReport) throws -> Void
    ) throws -> TrackpadStreamTermination
}

public final class TritonHIDDevice: TrackpadHIDStreaming {
    public static let vendorID: UInt16 = 0x28DE
    // 0x1304 = Proteus dongle, 0x1305 = Nereid dongle (SDL usb_ids.h).
    public static let productIDs: [UInt16] = [0x1304, 0x1305]
    // The dongle carries one controller slot per USB interface 2 through 5 (SDL's
    // HIDAPI_DriverSteamTriton_IsSupportedDevice); interfaces below 2 are the
    // lizard-mode boot keyboard/mouse.
    public static let dongleInterfaceNumbers = 2...5
    // Shortest meaningful report: a wireless-status packet (report ID + state byte).
    public static let minimumReportLength = 2
    // Shortest controller-state report: the 0x42/0x45 layout through both trackpads.
    public static let minimumStateReportLength = 30

    /// Whether a matched puck HID interface can carry controller reports. When macOS does not
    /// expose an interface number, fall back to requiring a state-report-capable input size so
    /// the lizard-mode boot keyboard/mouse interfaces stay excluded.
    public static func isControllerInterface(interfaceNumber: Int?, maximumInputReportSize: Int) -> Bool {
        if let interfaceNumber { return dongleInterfaceNumbers.contains(interfaceNumber) }
        return maximumInputReportSize >= minimumStateReportLength
    }

    #if canImport(IOKit)
    private struct OpenedInterface {
        let device: IOHIDDevice
        let buffer: UnsafeMutablePointer<UInt8>
        let capacity: Int
    }

    private let manager: IOHIDManager
    private let openedInterfaces: [OpenedInterface]
    private let callbackState = HIDCallbackState()
    #endif
    public let summary: TritonDeviceSummary

    public var summaryDescription: String { summary.description }

    #if canImport(IOKit)
    private init(manager: IOHIDManager, candidates: [(IOHIDDevice, TritonInterfaceSummary)], productID: UInt16) throws {
        var opened: [OpenedInterface] = []
        var openedSummaries: [TritonInterfaceSummary] = []
        var failures: [String] = []
        for (device, interfaceSummary) in candidates {
            let status = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
            guard status == kIOReturnSuccess else {
                let name = interfaceSummary.interfaceNumber.map(String.init) ?? "?"
                failures.append("interface \(name): IOKit status \(status)")
                continue
            }
            let capacity = max(interfaceSummary.maximumInputReportSize, TritonHIDDevice.minimumReportLength)
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
            buffer.initialize(repeating: 0, count: capacity)
            opened.append(OpenedInterface(device: device, buffer: buffer, capacity: capacity))
            openedSummaries.append(interfaceSummary)
        }
        guard !opened.isEmpty else {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            throw TrackIsBackError.device(
                "Could not passively open any SC2 puck interface (\(failures.joined(separator: "; ")))."
            )
        }
        self.manager = manager
        openedInterfaces = opened
        summary = TritonDeviceSummary(productID: productID, interfaces: openedSummaries)
    }
    #else
    private init(summary: TritonDeviceSummary) { self.summary = summary }
    #endif

    deinit {
        #if canImport(IOKit)
        for interface in openedInterfaces {
            IOHIDDeviceUnscheduleFromRunLoop(interface.device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDDeviceClose(interface.device, IOOptionBits(kIOHIDOptionsTypeNone))
            interface.buffer.deinitialize(count: interface.capacity)
            interface.buffer.deallocate()
        }
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        #endif
    }

    public static func probe() -> TritonDeviceSummary? {
        #if canImport(IOKit)
        guard let result = selectedDevices() else { return nil }
        IOHIDManagerClose(result.manager, IOOptionBits(kIOHIDOptionsTypeNone))
        return TritonDeviceSummary(productID: result.productID, interfaces: result.candidates.map(\.1))
        #else
        return nil
        #endif
    }

    public static func open() throws -> TritonHIDDevice {
        #if canImport(IOKit)
        guard let result = selectedDevices() else {
            throw TrackIsBackError.device("No Steam Controller 2 puck interface was found. Connect through the puck.")
        }
        return try TritonHIDDevice(manager: result.manager, candidates: result.candidates, productID: result.productID)
        #else
        throw TrackIsBackError.device("IOHID is unavailable on this platform.")
        #endif
    }

    #if canImport(IOKit)
    private final class InterfaceCallbackContext {
        let state: HIDCallbackState
        let slot: Int

        init(state: HIDCallbackState, slot: Int) {
            self.state = state
            self.slot = slot
        }
    }
    #endif

    public func stream(
        shouldContinue: () -> Bool,
        onWake: () throws -> Void,
        onReport: (TrackpadHIDReport) throws -> Void
    ) throws -> TrackpadStreamTermination {
        #if canImport(IOKit)
        let callback: IOHIDReportCallback = { context, result, _, _, _, report, length in
            guard result == kIOReturnSuccess, let context, length >= TritonHIDDevice.minimumReportLength else { return }
            let interfaceContext = Unmanaged<InterfaceCallbackContext>.fromOpaque(context).takeUnretainedValue()
            interfaceContext.state.append(
                slot: interfaceContext.slot,
                bytes: Array(UnsafeBufferPointer(start: report, count: length))
            )
        }
        let removalCallback: IOHIDCallback = { context, _, _ in
            guard let context else { return }
            Unmanaged<InterfaceCallbackContext>.fromOpaque(context).takeUnretainedValue().state.markRemoved()
        }
        let contexts = openedInterfaces.indices.map { index in
            InterfaceCallbackContext(state: callbackState, slot: index)
        }
        for (index, interface) in openedInterfaces.enumerated() {
            let context = Unmanaged.passUnretained(contexts[index]).toOpaque()
            IOHIDDeviceRegisterInputReportCallback(
                interface.device,
                interface.buffer,
                interface.capacity,
                callback,
                context
            )
            IOHIDDeviceRegisterRemovalCallback(interface.device, removalCallback, context)
            IOHIDDeviceScheduleWithRunLoop(interface.device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        }
        defer {
            for interface in openedInterfaces {
                IOHIDDeviceRegisterInputReportCallback(interface.device, interface.buffer, interface.capacity, nil, nil)
                IOHIDDeviceRegisterRemovalCallback(interface.device, nil, nil)
                IOHIDDeviceUnscheduleFromRunLoop(interface.device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            }
            withExtendedLifetime(contexts) {}
        }

        while shouldContinue(), !callbackState.isRemoved {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
            guard !callbackState.isRemoved else { break }
            for report in callbackState.drain() {
                guard !callbackState.isRemoved else { break }
                try onReport(report)
            }
            guard !callbackState.isRemoved else { break }
            try onWake()
        }
        return callbackState.isRemoved ? .deviceRemoved : .stopped
        #else
        throw TrackIsBackError.device("IOHID is unavailable on this platform.")
        #endif
    }

    #if canImport(IOKit)
    private struct Selection {
        let manager: IOHIDManager
        let candidates: [(IOHIDDevice, TritonInterfaceSummary)]
        let productID: UInt16
    }

    private static func selectedDevices() -> Selection? {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matches = productIDs.map { productID in
            [
                kIOHIDVendorIDKey as String: NSNumber(value: vendorID),
                kIOHIDProductIDKey as String: NSNumber(value: productID)
            ] as CFDictionary
        }
        IOHIDManagerSetDeviceMatchingMultiple(manager, matches as CFArray)
        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess,
              let deviceSet = IOHIDManagerCopyDevices(manager)
        else {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            return nil
        }

        let candidates = (deviceSet as NSSet).map { $0 as! IOHIDDevice }.compactMap { device -> (IOHIDDevice, UInt16, TritonInterfaceSummary)? in
            guard let productID = integerProperty(device, key: kIOHIDProductIDKey).map(UInt16.init),
                  let maximum = integerProperty(device, key: kIOHIDMaxInputReportSizeKey)
            else { return nil }
            let interface = interfaceNumber(device)
            guard isControllerInterface(interfaceNumber: interface, maximumInputReportSize: maximum) else { return nil }
            let summary = TritonInterfaceSummary(
                interfaceNumber: interface,
                usagePage: integerProperty(device, key: kIOHIDPrimaryUsagePageKey),
                usage: integerProperty(device, key: kIOHIDPrimaryUsageKey),
                maximumInputReportSize: maximum
            )
            return (device, productID, summary)
        }.sorted { lhs, rhs in
            (lhs.2.interfaceNumber ?? Int.max) < (rhs.2.interfaceNumber ?? Int.max)
        }

        guard let first = candidates.first else {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            return nil
        }
        return Selection(
            manager: manager,
            candidates: candidates.map { ($0.0, $0.2) },
            productID: first.1
        )
    }

    private static func integerProperty(_ device: IOHIDDevice, key: String) -> Int? {
        (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue
    }

    private static func interfaceNumber(_ device: IOHIDDevice) -> Int? {
        for key in ["USB Interface Number", "bInterfaceNumber", "InterfaceNumber", "IOUSBInterfaceNumber"] {
            if let value = integerProperty(device, key: key) { return value }
        }
        return nil
    }
    #endif
}
