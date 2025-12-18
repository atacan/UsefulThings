import Foundation

public struct PollingConfiguration: Sendable {
    let maxRetries: Int
    let baseDelay: TimeInterval
    let maxDelay: TimeInterval

    public static let `default` = PollingConfiguration(
        maxRetries: 10,
        baseDelay: 1.0,  // 1 second
        maxDelay: 32.0  // 32 seconds
    )
}

public enum PollingError: Error {
    case maxRetriesReached
    case conditionFailed(Error)
}

public func pollUntil<T>(
    configuration: PollingConfiguration = .default,
    operation: @escaping () async throws -> T,
    until condition: @escaping (T) throws -> Bool
) async throws -> T {
    var currentRetry = 0
    var currentDelay = configuration.baseDelay

    while true {
        let result = try await operation()

        if try condition(result) {
            return result
        }

        if currentRetry >= configuration.maxRetries {
            throw PollingError.maxRetriesReached
        }

        // Exponential backoff with jitter
        let jitter = Double.random(in: 0 ... (currentDelay / 2))
        let nanoseconds = UInt64((currentDelay + jitter) * 1_000_000_000)
        try await Task.sleep(nanoseconds: nanoseconds)

        currentRetry += 1
        currentDelay = min(currentDelay * 2, configuration.maxDelay)
    }
}
