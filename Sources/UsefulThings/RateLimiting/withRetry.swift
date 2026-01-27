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

public struct RetryPredicate: Sendable {
    private let shouldRetry: @Sendable (any Error, Int) -> Bool
    
    public init(_ predicate: @escaping @Sendable (any Error, Int) -> Bool) {
        self.shouldRetry = predicate
    }
    
    public func callAsFunction(error: any Error, attempt: Int) -> Bool {
        shouldRetry(error, attempt)
    }
    
    public static let always = RetryPredicate { _, _ in true }
    public static let never = RetryPredicate { _, _ in false }
    
    public static func on<E: Error>(_ errorType: E.Type) -> RetryPredicate {
        RetryPredicate { error, _ in error is E }
    }
    
    public static func onErrors<E: Error & Equatable & Sendable>(_ errors: E...) -> RetryPredicate {
        let errorList = errors
        return RetryPredicate { error, _ in
            guard let typedError = error as? E else { return false }
            return errorList.contains(typedError)
        }
    }
    
    public static func except<E: Error>(_ errorType: E.Type) -> RetryPredicate {
        RetryPredicate { error, _ in !(error is E) }
    }
    
    public func and(_ other: RetryPredicate) -> RetryPredicate {
        RetryPredicate { error, attempt in
            self(error: error, attempt: attempt) && other(error: error, attempt: attempt)
        }
    }
    
    public func or(_ other: RetryPredicate) -> RetryPredicate {
        RetryPredicate { error, attempt in
            self(error: error, attempt: attempt) || other(error: error, attempt: attempt)
        }
    }
    
    public var negated: RetryPredicate {
        RetryPredicate { error, attempt in !self(error: error, attempt: attempt) }
    }
}

// MARK: - Retry Event Handler

public struct RetryEventHandler: Sendable {
    public let onRetry: @Sendable (Int, any Error, Duration) async -> Void
    
    public init(onRetry: @escaping @Sendable (Int, any Error, Duration) async -> Void) {
        self.onRetry = onRetry
    }
    
    public static let none = RetryEventHandler { _, _, _ in }
    
    public static func log(
        using logger: @escaping @Sendable (String) -> Void = { print($0) }
    ) -> RetryEventHandler {
        RetryEventHandler { attempt, error, delay in
            logger("Retry attempt \(attempt) after error: \(error). Waiting \(delay)...")
        }
    }
}

// MARK: - withRetry Implementation

public func withRetry<T: Sendable>(
    configuration: RetryConfiguration = .default,
    predicate: RetryPredicate = .always,
    rateLimiter: (any RateLimiter)? = nil,
    eventHandler: RetryEventHandler = .none,
    operation: @Sendable () async throws -> T
) async throws -> T {
    var allErrors: [any Error] = []
    
    for attempt in 1...configuration.maxAttempts {
        try Task.checkCancellation()
        
        if let limiter = rateLimiter {
            try await limiter.acquire()
        }
        
        do {
            return try await operation()
        } catch {
            allErrors.append(error)
            
            guard attempt < configuration.maxAttempts else {
                throw RetryError(
                    attempts: attempt,
                    lastError: error,
                    allErrors: allErrors
                )
            }
            
            guard predicate(error: error, attempt: attempt) else {
                throw error
            }
            
            let delay = configuration.delay(forAttempt: attempt + 1)
            await eventHandler.onRetry(attempt, error, delay)
            
            if delay > .zero {
                try await Task.sleep(for: delay)
            }
        }
    }
    
    fatalError("Unreachable")
}

public func withRetry<T: Sendable>(
    maxAttempts: Int,
    delay: Duration = .seconds(1),
    operation: @Sendable () async throws -> T
) async throws -> T {
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

public func withRetry<T: Sendable>(
    configuration: RetryConfiguration = .default,
    timeout: Duration,
    predicate: RetryPredicate = .always,
    operation: @Sendable @escaping () async throws -> T
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
        
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}

public func withAdaptiveRetry<T: Sendable>(
    configuration: RetryConfiguration = .default,
    rateLimiter: AdaptiveRateLimiter,
    isRateLimitError: @escaping @Sendable (any Error) -> Bool,
    operation: @Sendable () async throws -> T
) async throws -> T {
    try await withRetry(
        configuration: configuration,
        predicate: .always,
        rateLimiter: rateLimiter
    ) {
        do {
            let result = try await operation()
            await rateLimiter.recordSuccess()
            return result
        } catch {
            if isRateLimitError(error) {
                await rateLimiter.recordRateLimited()
            }
            throw error
        }
    }
}

// MARK: - Circuit Breaker

public actor CircuitBreaker {
    public enum State: Sendable {
        case closed
        case open
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
    
    public func execute<T: Sendable>(
        operation: @Sendable () async throws -> T
    ) async throws -> T {
        try checkState()
        
        do {
            let result = try await operation()
            recordSuccess()
            return result
        } catch {
            recordFailure()
            throw error
        }
    }
    
    private func checkState() throws {
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

public enum CircuitBreakerError: Error, Sendable {
    case open(retryAfter: Duration)
}

// MARK: - Combined Resilience Helper

public func withResilience<T: Sendable>(
    rateLimiter: (any RateLimiter)? = nil,
    circuitBreaker: CircuitBreaker? = nil,
    retryConfiguration: RetryConfiguration = .default,
    retryPredicate: RetryPredicate = .always,
    operation: @Sendable () async throws -> T
) async throws -> T {
    try await withRetry(
        configuration: retryConfiguration,
        predicate: retryPredicate,
        rateLimiter: rateLimiter
    ) {
        if let cb = circuitBreaker {
            return try await cb.execute(operation: operation)
        } else {
            return try await operation()
        }
    }
}
