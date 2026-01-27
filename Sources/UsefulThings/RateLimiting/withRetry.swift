import func Foundation.pow

// MARK: - Retry Configuration

public struct RetryConfiguration: Sendable {
    public let maxAttempts: Int
    public let initialDelay: Duration
    public let maxDelay: Duration
    public let backoffMultiplier: Double
    public let jitterFactor: Double

    public init(
        maxAttempts: Int = 3,
        initialDelay: Duration = .seconds(1),
        maxDelay: Duration = .seconds(60),
        backoffMultiplier: Double = 2.0,
        jitterFactor: Double = 0.1
    ) {
        precondition(maxAttempts >= 1)
        precondition(backoffMultiplier >= 1.0)
        precondition(jitterFactor >= 0 && jitterFactor <= 1.0)

        self.maxAttempts = maxAttempts
        self.initialDelay = initialDelay
        self.maxDelay = maxDelay
        self.backoffMultiplier = backoffMultiplier
        self.jitterFactor = jitterFactor
    }

    public static let `default` = RetryConfiguration()

    public static let aggressive = RetryConfiguration(
        maxAttempts: 5,
        initialDelay: .milliseconds(100),
        maxDelay: .seconds(10),
        backoffMultiplier: 1.5,
        jitterFactor: 0.2
    )

    public static let conservative = RetryConfiguration(
        maxAttempts: 3,
        initialDelay: .seconds(5),
        maxDelay: .seconds(120),
        backoffMultiplier: 3.0,
        jitterFactor: 0.1
    )

    public static let noRetry = RetryConfiguration(maxAttempts: 1)

    public func delay(forAttempt attempt: Int) -> Duration {
        guard attempt > 1 else { return .zero }

        let exponentialDelay = initialDelay.toSeconds * pow(backoffMultiplier, Double(attempt - 2))
        let clampedDelay = min(exponentialDelay, maxDelay.toSeconds)

        let jitterRange = clampedDelay * jitterFactor
        let jitter = Double.random(in: -jitterRange...jitterRange)
        let finalDelay = max(0, clampedDelay + jitter)

        return .seconds(finalDelay)
    }
}

// MARK: - Retry Predicate

public struct RetryPredicate<E: Error & Sendable>: Sendable {
    private let shouldRetry: @Sendable (E, Int) -> Bool

    public init(_ predicate: @escaping @Sendable (E, Int) -> Bool) {
        self.shouldRetry = predicate
    }

    public func callAsFunction(error: E, attempt: Int) -> Bool {
        shouldRetry(error, attempt)
    }

    public static var always: RetryPredicate<E> { RetryPredicate { _, _ in true } }
    public static var never: RetryPredicate<E> { RetryPredicate { _, _ in false } }

    /// Only retry if the error is of a specific type
    public static func on<Specific: Error>(_ errorType: Specific.Type) -> RetryPredicate<E> {
        RetryPredicate { error, _ in error is Specific }
    }

    /// Don't retry on specific error type
    public static func except<Specific: Error>(_ errorType: Specific.Type) -> RetryPredicate<E> {
        RetryPredicate { error, _ in !(error is Specific) }
    }

    /// Only retry up to N times for specific error type
    public static func limited<Specific: Error>(_ errorType: Specific.Type, maxAttempts: Int) -> RetryPredicate<E> {
        RetryPredicate { error, attempt in
            guard error is Specific else { return true }
            return attempt < maxAttempts
        }
    }

    /// Combine predicates with AND
    public func and(_ other: RetryPredicate<E>) -> RetryPredicate<E> {
        RetryPredicate { error, attempt in
            self(error: error, attempt: attempt) && other(error: error, attempt: attempt)
        }
    }

    /// Combine predicates with OR
    public func or(_ other: RetryPredicate<E>) -> RetryPredicate<E> {
        RetryPredicate { error, attempt in
            self(error: error, attempt: attempt) || other(error: error, attempt: attempt)
        }
    }

    /// Negate the predicate
    public var negated: RetryPredicate<E> {
        RetryPredicate { error, attempt in
            !self(error: error, attempt: attempt)
        }
    }
}

extension RetryPredicate where E: Equatable {
    /// Retry on specific error values (requires Equatable errors)
    public static func onErrors(_ errors: E...) -> RetryPredicate<E> {
        let errorList = errors
        return RetryPredicate { error, _ in
            errorList.contains(error)
        }
    }
}

// MARK: - Retry Event Handler

public struct RetryEventHandler<E: Error & Sendable>: Sendable {
    public let onRetry: @Sendable (Int, E, Duration) async -> Void

    public init(onRetry: @escaping @Sendable (Int, E, Duration) async -> Void) {
        self.onRetry = onRetry
    }

    public static var none: RetryEventHandler<E> { RetryEventHandler { _, _, _ in } }

    public static func log(
        using logger: @escaping @Sendable (String) -> Void = { print($0) }
    ) -> RetryEventHandler<E> {
        RetryEventHandler { attempt, error, delay in
            logger("Retry attempt \(attempt) after error: \(error). Waiting \(delay)...")
        }
    }
}

public struct RetryError<E: Error & Sendable>: Error, Sendable {
    public let attempts: Int
    public let lastError: E
    public let allErrors: [E]

    public var description: String {
        "Failed after \(attempts) attempts. Last error: \(lastError)"
    }
}

// MARK: - withRetry Implementation (Typed Throws - No Rate Limiter)

/// Executes an async operation with automatic retries using typed throws
public func withRetry<T: Sendable, E: Error & Sendable>(
    configuration: RetryConfiguration = .default,
    predicate: RetryPredicate<E> = .always,
    eventHandler: RetryEventHandler<E> = .none,
    operation: @Sendable () async throws(E) -> T
) async throws(RetryError<E>) -> T {
    var allErrors: [E] = []
    var lastError: E?

    for attempt in 1...configuration.maxAttempts {
        // Check cancellation - if cancelled before any attempt, propagate via the operation
        if Task.isCancelled, let error = lastError {
            throw RetryError(attempts: attempt - 1, lastError: error, allErrors: allErrors)
        }

        do {
            return try await operation()
        } catch let operationError {
            allErrors.append(operationError)
            lastError = operationError

            guard attempt < configuration.maxAttempts else {
                throw RetryError(
                    attempts: attempt,
                    lastError: operationError,
                    allErrors: allErrors
                )
            }

            guard predicate(error: operationError, attempt: attempt) else {
                throw RetryError(
                    attempts: attempt,
                    lastError: operationError,
                    allErrors: allErrors
                )
            }

            let delay = configuration.delay(forAttempt: attempt + 1)
            await eventHandler.onRetry(attempt, operationError, delay)

            if delay > .zero {
                do {
                    try await Task.sleep(for: delay)
                } catch {
                    // Sleep was interrupted (likely cancellation)
                    // Use the operation error, not the sleep interruption error
                    throw RetryError(attempts: attempt, lastError: operationError, allErrors: allErrors)
                }
            }
        }
    }

    fatalError("Unreachable")
}

/// Convenience overload with simpler parameters (typed throws)
public func withRetry<T: Sendable, E: Error & Sendable>(
    maxAttempts: Int,
    delay: Duration = .seconds(1),
    operation: @Sendable () async throws(E) -> T
) async throws(RetryError<E>) -> T {
    try await withRetry(
        configuration: RetryConfiguration(
            maxAttempts: maxAttempts,
            initialDelay: delay,
            backoffMultiplier: 1.0,
            jitterFactor: 0
        ),
        operation: operation
    )
}

// MARK: - withRetry with Rate Limiter (Generic, Untyped throws)

/// Executes an async operation with automatic retries and rate limiting
/// Note: Uses untyped throws due to Swift compiler limitations with typed throws + generics + async
public func withRetry<T: Sendable, L: RateLimiter>(
    configuration: RetryConfiguration = .default,
    rateLimiter: L,
    operation: @Sendable () async throws -> T
) async throws -> T {
    var allErrors: [Error] = []

    for attempt in 1...configuration.maxAttempts {
        try Task.checkCancellation()
        try await rateLimiter.acquire()

        do {
            return try await operation()
        } catch {
            allErrors.append(error)

            guard attempt < configuration.maxAttempts else {
                throw error
            }

            let delay = configuration.delay(forAttempt: attempt + 1)

            if delay > .zero {
                try await Task.sleep(for: delay)
            }
        }
    }

    fatalError("Unreachable")
}

/// Retry with timeout for entire retry sequence
public func withRetry<T: Sendable, E: Error & Sendable>(
    configuration: RetryConfiguration = .default,
    timeout: Duration,
    predicate: RetryPredicate<E> = .always,
    operation: @Sendable @escaping () async throws(E) -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await withRetry(
                configuration: configuration,
                predicate: predicate,
                operation: operation
            )
        }

        group.addTask {
            try await Task.sleep(for: timeout)
            throw RateLimiterError.timeout
        }

        // One of the two tasks will always complete (operation or timeout)
        guard let result = try await group.next() else {
            throw RateLimiterError.timeout
        }
        group.cancelAll()
        return result
    }
}

// MARK: - withRetry with Adaptive Rate Limiter

/// Specialized retry for APIs with rate limiting that provides feedback
public func withAdaptiveRetry<T: Sendable>(
    configuration: RetryConfiguration = .default,
    rateLimiter: AdaptiveRateLimiter,
    isRateLimitError: @escaping @Sendable (Error) -> Bool,
    operation: @Sendable () async throws -> T
) async throws -> T {
    var allErrors: [Error] = []

    for attempt in 1...configuration.maxAttempts {
        try Task.checkCancellation()
        try await rateLimiter.acquire()

        do {
            let result = try await operation()
            await rateLimiter.recordSuccess()
            return result
        } catch {
            allErrors.append(error)

            if isRateLimitError(error) {
                await rateLimiter.recordRateLimited()
            }

            guard attempt < configuration.maxAttempts else {
                throw error
            }

            let delay = configuration.delay(forAttempt: attempt + 1)

            if delay > .zero {
                try await Task.sleep(for: delay)
            }
        }
    }

    fatalError("Unreachable")
}

// MARK: - Circuit Breaker

/// Circuit Breaker pattern to prevent cascading failures
public actor CircuitBreaker {
    public enum State: Sendable {
        /// Normal operation
        case closed
        /// Failing, reject requests
        case open
        /// Testing if service recovered
        case halfOpen
    }

    private var state: State = .closed
    private var failureCount: Int = 0
    private var successCount: Int = 0
    private var lastFailureTime: ContinuousClock.Instant?

    private let failureThreshold: Int
    private let successThreshold: Int
    private let timeout: Duration
    private let clock = ContinuousClock()

    public init(
        failureThreshold: Int = 5,
        successThreshold: Int = 2,
        timeout: Duration = .seconds(30)
    ) {
        self.failureThreshold = failureThreshold
        self.successThreshold = successThreshold
        self.timeout = timeout
    }

    public var currentState: State { state }

    public func execute<T: Sendable, E: Error>(
        operation: @Sendable () async throws(E) -> T
    ) async throws(CircuitBreakerFailure<E>) -> T {
        do {
            try checkState()
        } catch {
            throw .circuitOpen(retryAfter: error.retryAfter)
        }

        do {
            let result = try await operation()
            recordSuccess()
            return result
        } catch {
            recordFailure()
            throw .operationFailed(error)
        }
    }

    /// Untyped version for simpler usage
    public func run<T: Sendable>(
        _ operation: @Sendable () async throws -> T
    ) async throws -> T {
        try checkStateUntyped()

        do {
            let result = try await operation()
            recordSuccess()
            return result
        } catch {
            recordFailure()
            throw error
        }
    }

    private func checkState() throws(CircuitBreakerOpenError) {
        switch state {
        case .closed:
            return

        case .open:
            guard let lastFailure = lastFailureTime else {
                state = .halfOpen
                return
            }

            let elapsed = lastFailure.duration(to: clock.now)
            if elapsed >= timeout {
                state = .halfOpen
                successCount = 0
            } else {
                throw CircuitBreakerOpenError(retryAfter: timeout - elapsed)
            }

        case .halfOpen:
            return
        }
    }

    private func checkStateUntyped() throws {
        switch state {
        case .closed:
            return

        case .open:
            guard let lastFailure = lastFailureTime else {
                state = .halfOpen
                return
            }

            let elapsed = lastFailure.duration(to: clock.now)
            if elapsed >= timeout {
                state = .halfOpen
                successCount = 0
            } else {
                throw CircuitBreakerError.open(retryAfter: timeout - elapsed)
            }

        case .halfOpen:
            return
        }
    }

    private func recordSuccess() {
        switch state {
        case .closed:
            failureCount = 0

        case .halfOpen:
            successCount += 1
            if successCount >= successThreshold {
                state = .closed
                failureCount = 0
                successCount = 0
            }

        case .open:
            break
        }
    }

    private func recordFailure() {
        lastFailureTime = clock.now

        switch state {
        case .closed:
            failureCount += 1
            if failureCount >= failureThreshold {
                state = .open
            }

        case .halfOpen:
            state = .open
            successCount = 0

        case .open:
            break
        }
    }

    public func reset() {
        state = .closed
        failureCount = 0
        successCount = 0
        lastFailureTime = nil
    }
}

public struct CircuitBreakerOpenError: Error, Sendable {
    public let retryAfter: Duration
}

public enum CircuitBreakerFailure<E: Error>: Error {
    case circuitOpen(retryAfter: Duration)
    case operationFailed(E)
}

public enum CircuitBreakerError: Error, Sendable {
    case open(retryAfter: Duration)
}

// MARK: - Combined Resilience Helper

/// Combines rate limiting, retry, and circuit breaker
public func withResilience<T: Sendable, L: RateLimiter>(
    rateLimiter: L,
    circuitBreaker: CircuitBreaker? = nil,
    retryConfiguration: RetryConfiguration = .default,
    operation: @Sendable () async throws -> T
) async throws -> T {
    for attempt in 1...retryConfiguration.maxAttempts {
        try Task.checkCancellation()
        try await rateLimiter.acquire()

        do {
            if let cb = circuitBreaker {
                return try await cb.run(operation)
            } else {
                return try await operation()
            }
        } catch {
            guard attempt < retryConfiguration.maxAttempts else {
                throw error
            }

            let delay = retryConfiguration.delay(forAttempt: attempt + 1)

            if delay > .zero {
                try await Task.sleep(for: delay)
            }
        }
    }

    fatalError("Unreachable")
}

/// Combines retry and circuit breaker (no rate limiter)
public func withResilience<T: Sendable>(
    circuitBreaker: CircuitBreaker? = nil,
    retryConfiguration: RetryConfiguration = .default,
    operation: @Sendable () async throws -> T
) async throws -> T {
    for attempt in 1...retryConfiguration.maxAttempts {
        try Task.checkCancellation()

        do {
            if let cb = circuitBreaker {
                return try await cb.run(operation)
            } else {
                return try await operation()
            }
        } catch {
            guard attempt < retryConfiguration.maxAttempts else {
                throw error
            }

            let delay = retryConfiguration.delay(forAttempt: attempt + 1)

            if delay > .zero {
                try await Task.sleep(for: delay)
            }
        }
    }

    fatalError("Unreachable")
}
