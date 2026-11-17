import Foundation

/// Combines network events into one delayed check, with no retries.
@MainActor
public enum NetworkStabilizer {
    public static func run(
        timeout: Duration = .seconds(30),
        initialDelay: Duration = .seconds(3),
        probe: @escaping @MainActor @Sendable () async throws -> IPv4Address?
    ) async -> Bool {
        precondition(timeout > .zero && initialDelay >= .zero)
        return await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await collect(initialDelay: initialDelay, probe: probe)
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return false
            }
            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }
    }

    private static func collect(
        initialDelay: Duration,
        probe: @escaping @MainActor @Sendable () async throws -> IPv4Address?
    ) async -> Bool {
        // Superseding network events cancel this wait, combining a burst of
        // interface/route changes before any HTTP request has been started.
        do { try await Task.sleep(for: initialDelay) }
        catch { return false }
        guard !Task.isCancelled else { return false }
        do {
            let address = try await probe()
            return !Task.isCancelled && address != nil
        } catch {
            return false
        }
    }
}
