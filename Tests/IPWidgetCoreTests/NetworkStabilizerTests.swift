import Foundation
import Testing
@testable import IPWidgetCore

@MainActor
@Suite("Delayed network check")
struct NetworkStabilizerTests {
    private let address = IPv4Address(rawValue: 0x08080808)

    @Test func makesExactlyOneSuccessfulCheck() async {
        var count = 0
        let result = await NetworkStabilizer.run(initialDelay: .zero) {
            count += 1
            return address
        }
        #expect(result)
        #expect(count == 1)
    }

    @Test func failureDoesNotTriggerRetries() async {
        var count = 0
        let result = await NetworkStabilizer.run(initialDelay: .zero) {
            count += 1
            return nil
        }
        #expect(!result)
        #expect(count == 1)
    }

    @Test func requestStartsAfterSettlingDelay() async {
        let clock = ContinuousClock()
        let started = clock.now
        let result = await NetworkStabilizer.run(initialDelay: .milliseconds(20)) {
            #expect(started.duration(to: clock.now) >= .milliseconds(20))
            return address
        }
        #expect(result)
    }

    @Test func timeoutCancelsAnInFlightRequest() async {
        var cancelled = false
        let result = await NetworkStabilizer.run(timeout: .milliseconds(20), initialDelay: .zero) {
            do { try await Task.sleep(for: .seconds(10)) }
            catch { cancelled = true }
            return nil
        }
        #expect(!result)
        #expect(cancelled)
    }

    @Test func cancellationDuringDelayMakesNoRequests() async {
        var count = 0
        let task = Task {
            await NetworkStabilizer.run(initialDelay: .seconds(10)) {
                count += 1
                return address
            }
        }
        task.cancel()
        #expect(await task.value == false)
        #expect(count == 0)
    }

    @Test func rateLimitDoesNotTriggerRetries() async {
        var count = 0
        let result = await NetworkStabilizer.run(initialDelay: .zero) {
            count += 1
            throw TwoIPError.rateLimited(until: Date().addingTimeInterval(60))
        }
        #expect(!result)
        #expect(count == 1)
    }
}
