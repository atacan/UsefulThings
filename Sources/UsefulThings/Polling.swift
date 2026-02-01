import func Foundation.pow

public struct PollingConfiguration: Sendable {
    public let maxAttempts: Int
    public let baseDelay: Duration
    public let maxDelay: Duration
    public let backoffMultiplier: Double
    public let jitterFactor: Double
    public let timeout: Duration?

    public init(
        maxAttempts: Int = 10,
        baseDelay: Duration = .seconds(1),
        maxDelay: Duration = .seconds(32),
        backoffMultiplier: Double = 2.0,
        jitterFactor: Double = 0.5,
        timeout: Duration? = nil
    ) {
        self.maxAttempts = maxAttempts
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
        self.backoffMultiplier = backoffMultiplier
        self.jitterFactor = jitterFactor
        self.timeout = timeout
    }

    public static let `default` = PollingConfiguration()

    func delay(forAttempt attempt: Int) -> Duration {
        let base = baseDelay * pow(backoffMultiplier, Double(attempt))
        let capped = min(base, maxDelay)
        let jitter = Double.random(in: -jitterFactor...jitterFactor)
        return capped * (1.0 + jitter)
    }
}

public enum PollingError: Error {
    case maxAttemptsReached
    case timedOut
}

public func withPolling<T, C: Clock>(
    configuration: PollingConfiguration = .default,
    clock: C,
    until condition: @escaping (T) throws -> Bool,
    operation: @escaping () async throws -> T
) async throws -> T where C.Duration == Duration {
    let deadline: C.Instant? = if let timeout = configuration.timeout {
        clock.now.advanced(by: timeout)
    } else {
        nil
    }

    for attempt in 0..<configuration.maxAttempts {
        try Task.checkCancellation()

        if let deadline, clock.now >= deadline {
            throw PollingError.timedOut
        }

        let result = try await operation()

        if try condition(result) {
            return result
        }

        if attempt < configuration.maxAttempts - 1 {
            let delay = configuration.delay(forAttempt: attempt)

            if let deadline {
                let remaining = clock.now.duration(to: deadline)
                guard delay < remaining else {
                    throw PollingError.timedOut
                }
            }

            try await clock.sleep(for: delay)
        }
    }

    throw PollingError.maxAttemptsReached
}

public func withPolling<T>(
    configuration: PollingConfiguration = .default,
    until condition: @escaping (T) throws -> Bool,
    operation: @escaping () async throws -> T
) async throws -> T {
    try await withPolling(
        configuration: configuration,
        clock: ContinuousClock(),
        until: condition,
        operation: operation
    )
}

@available(*, deprecated, renamed: "withPolling(configuration:until:operation:)")
public func pollUntil<T>(
    configuration: PollingConfiguration = .default,
    operation: @escaping () async throws -> T,
    until condition: @escaping (T) throws -> Bool
) async throws -> T {
    try await withPolling(configuration: configuration, until: condition, operation: operation)
}
