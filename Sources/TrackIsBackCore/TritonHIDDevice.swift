import Foundation
import Synchronization
#if canImport(IOKit)
import IOKit
import IOKit.hid
import IOKit.hidsystem
#endif

public struct TritonDeviceSummary: Sendable {
    public let productID: UInt16
    public let interfaceNumber: Int?
    public let usagePage: Int?
    public let usage: Int?
    public let maximumInputReportSize: Int

    public var description: String {
        let interfaceText = interfaceNumber.map(String.init) ?? "unknown"
        let usageText: String
        if let usagePage, let usage {
            usageText = String(format: "0x%04X/0x%04X", usagePage, usage)
        } else {
            usageText = "unknown"
        }
        return String(
            format: "Valve 0x28DE:0x%04X interface=%@ usage=%@ inputReport=%d",
            productID,
            interfaceText,
            usageText,
            maximumInputReportSize
        )
    }
}

#if canImport(IOKit)
private final class HIDCallbackState: Sendable {
    private struct State: ~Copyable {
        var reports: [([UInt8], UInt64)] = []
        var deviceRemoved = false
    }

    private let state = Mutex(State())

    func append(_ bytes: [UInt8]) {
        state.withLock { state in
            guard !state.deviceRemoved else { return }
            state.reports.append((bytes, DispatchTime.now().uptimeNanoseconds))
        }
    }

    func drain() -> [([UInt8], UInt64)] {
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

public protocol TrackpadHIDStreaming {
    var summaryDescription: String { get }
    func stream(
        shouldContinue: () -> Bool,
        onReport: ([UInt8], UInt64) throws -> Void
    ) throws -> TrackpadStreamTermination
}

public final class TritonHIDDevice: TrackpadHIDStreaming {
    public static let vendorID: UInt16 = 0x28DE
    public static let productIDs: [UInt16] = [0x1304, 0x1305]
    public static let expectedReportLength = 54

    #if canImport(IOKit)
    private let manager: IOHIDManager
    private let device: IOHIDDevice
    private let buffer: UnsafeMutablePointer<UInt8>
    private let callbackState = HIDCallbackState()
    #endif
    public let summary: TritonDeviceSummary

    public var summaryDescription: String { summary.description }

    #if canImport(IOKit)
    private init(manager: IOHIDManager, device: IOHIDDevice, summary: TritonDeviceSummary) throws {
        self.manager = manager
        self.device = device
        self.summary = summary
        buffer = .allocate(capacity: summary.maximumInputReportSize)
        buffer.initialize(repeating: 0, count: summary.maximumInputReportSize)
        let status = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard status == kIOReturnSuccess else {
            buffer.deinitialize(count: summary.maximumInputReportSize)
            buffer.deallocate()
            throw TrackIsBackError.device("Could not passively open the SC2 puck interface (IOKit status \(status)).")
        }
    }
    #else
    private init(summary: TritonDeviceSummary) { self.summary = summary }
    #endif

    deinit {
        #if canImport(IOKit)
        IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        buffer.deinitialize(count: summary.maximumInputReportSize)
        buffer.deallocate()
        #endif
    }

    public static func probe() -> TritonDeviceSummary? {
        #if canImport(IOKit)
        guard let result = selectedDevice() else { return nil }
        IOHIDManagerClose(result.manager, IOOptionBits(kIOHIDOptionsTypeNone))
        return result.summary
        #else
        return nil
        #endif
    }

    public static func open() throws -> TritonHIDDevice {
        #if canImport(IOKit)
        guard let result = selectedDevice() else {
            throw TrackIsBackError.device("No Steam Controller 2 puck interface was found. Connect through the puck.")
        }
        return try TritonHIDDevice(manager: result.manager, device: result.device, summary: result.summary)
        #else
        throw TrackIsBackError.device("IOHID is unavailable on this platform.")
        #endif
    }

    public func stream(
        shouldContinue: () -> Bool,
        onReport: ([UInt8], UInt64) throws -> Void
    ) throws -> TrackpadStreamTermination {
        #if canImport(IOKit)
        let callback: IOHIDReportCallback = { context, result, _, _, _, report, length in
            guard result == kIOReturnSuccess, let context, length == TritonHIDDevice.expectedReportLength else { return }
            let state = Unmanaged<HIDCallbackState>.fromOpaque(context).takeUnretainedValue()
            state.append(Array(UnsafeBufferPointer(start: report, count: length)))
        }
        let removalCallback: IOHIDCallback = { context, _, _ in
            guard let context else { return }
            Unmanaged<HIDCallbackState>.fromOpaque(context).takeUnretainedValue().markRemoved()
        }
        let context = Unmanaged.passUnretained(callbackState).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(
            device,
            buffer,
            summary.maximumInputReportSize,
            callback,
            context
        )
        IOHIDDeviceRegisterRemovalCallback(device, removalCallback, context)
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        defer {
            IOHIDDeviceRegisterInputReportCallback(device, buffer, summary.maximumInputReportSize, nil, nil)
            IOHIDDeviceRegisterRemovalCallback(device, nil, nil)
            IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        }

        while shouldContinue(), !callbackState.isRemoved {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
            guard !callbackState.isRemoved else { break }
            for (bytes, timestamp) in callbackState.drain() {
                guard !callbackState.isRemoved else { break }
                try onReport(bytes, timestamp)
            }
        }
        return callbackState.isRemoved ? .deviceRemoved : .stopped
        #else
        throw TrackIsBackError.device("IOHID is unavailable on this platform.")
        #endif
    }

    #if canImport(IOKit)
    private struct Selection {
        let manager: IOHIDManager
        let device: IOHIDDevice
        let summary: TritonDeviceSummary
    }

    private static func selectedDevice() -> Selection? {
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

        let candidates = (deviceSet as NSSet).map { $0 as! IOHIDDevice }.compactMap { device -> (IOHIDDevice, TritonDeviceSummary, Int)? in
            guard let productID = integerProperty(device, key: kIOHIDProductIDKey).map(UInt16.init),
                  let maximum = integerProperty(device, key: kIOHIDMaxInputReportSizeKey),
                  maximum == expectedReportLength
            else { return nil }
            let interface = interfaceNumber(device)
            let usagePage = integerProperty(device, key: kIOHIDPrimaryUsagePageKey)
            let usage = integerProperty(device, key: kIOHIDPrimaryUsageKey)
            let summary = TritonDeviceSummary(
                productID: productID,
                interfaceNumber: interface,
                usagePage: usagePage,
                usage: usage,
                maximumInputReportSize: maximum
            )
            var score = 0
            if usagePage == 0x0001, usage == 0x0002 { score += 1_000 }
            if interface == 2 { score += 100 }
            return (device, summary, score)
        }.sorted { lhs, rhs in
            if lhs.2 != rhs.2 { return lhs.2 > rhs.2 }
            return (lhs.1.interfaceNumber ?? Int.max) < (rhs.1.interfaceNumber ?? Int.max)
        }

        guard let selected = candidates.first else {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            return nil
        }
        return Selection(manager: manager, device: selected.0, summary: selected.1)
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
