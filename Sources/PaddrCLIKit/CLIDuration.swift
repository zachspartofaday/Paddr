import Foundation
import PaddrCore

package struct CLIDuration: Equatable, Sendable {
    package let runtimeValue: Duration

    package init(argument: String) throws {
        guard let seconds = Double(argument), seconds.isFinite else {
            throw PaddrError.configuration("--duration requires a finite number.")
        }
        guard seconds > 0 else {
            throw PaddrError.configuration("--duration must be positive.")
        }

        let largestExactlyConvertibleSecondCount = Double(UInt64.max / 1_000_000_000)
        guard seconds <= largestExactlyConvertibleSecondCount else {
            throw PaddrError.configuration("--duration is too large.")
        }

        let duration = Duration.seconds(seconds)
        _ = try TrackpadRuntime.validatedDurationNanoseconds(duration)
        runtimeValue = duration
    }
}
