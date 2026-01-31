import Testing
@testable import UsefulThings

enum TestError: Error, Sendable, Equatable {
    case failed
    case networkError
    case timeout
}

// Thread-safe counter for testing
actor Counter {
    var value: Int = 0

    func increment() -> Int {
        value += 1
        return value
    }

    func get() -> Int {
        value
    }
}

// Thread-safe array for testing
actor ErrorCollector<E: Sendable> {
    var errors: [E] = []

    func append(_ error: E) {
        errors.append(error)
    }

    func getAll() -> [E] {
        errors
    }

    func count() -> Int {
        errors.count
    }
}

@Suite("Retry API Tests")
struct RetryAPITests {

    // MARK: - Test with explicit typed throws

    @Test("withRetry works with explicitly typed throws closure")
    func explicitTypedThrows() async throws {
        let counter = Counter()

        let result = try await withRetry(
            configuration: RetryConfiguration(maxAttempts: 3)
        ) { () async throws(TestError) -> String in
            let attempt = await counter.increment()
            if attempt < 2 {
                throw TestError.failed
            }
            return "success"
        }

        #expect(result == "success")
        let finalCount = await counter.get()
        #expect(finalCount == 2)
    }

    // MARK: - Test with regular throws (what most users will write)

    @Test("withRetry works with regular throws closure")
    func regularThrows() async throws {
        let counter = Counter()

        // This is what most users will write - regular throws, not typed throws
        let result = try await withRetry(
            configuration: RetryConfiguration(maxAttempts: 3)
        ) {
            let attempt = await counter.increment()
            if attempt < 2 {
                throw TestError.failed
            }
            return "success"
        }

        #expect(result == "success")
        let finalCount = await counter.get()
        #expect(finalCount == 2)
    }

    // MARK: - Test with rate limiter (uses untyped throws)

    @Test("withRetry with rate limiter works")
    func withRateLimiter() async throws {
        let limiter = TokenBucketRateLimiter(capacity: 10, refillRate: 10.0)
        let counter = Counter()

        let result = try await withRetry(
            configuration: RetryConfiguration(maxAttempts: 3),
            rateLimiter: limiter
        ) {
            let attempt = await counter.increment()
            if attempt < 2 {
                throw TestError.failed
            }
            return "success"
        }

        #expect(result == "success")
        let finalCount = await counter.get()
        #expect(finalCount == 2)
    }

    // MARK: - Test predicate with typed error

    @Test("RetryPredicate works with typed error")
    func predicateTypedError() async throws {
        let counter = Counter()

        let predicate = RetryPredicate<TestError> { error, _ in
            error == .networkError  // Only retry network errors
        }

        // This should NOT retry because we throw .failed, not .networkError
        do {
            _ = try await withRetry(
                configuration: RetryConfiguration(maxAttempts: 3),
                predicate: predicate
            ) { () async throws(TestError) -> String in
                _ = await counter.increment()
                throw TestError.failed
            }
            Issue.record("Should have thrown")
        } catch {
            // Expected - predicate rejected retry
            let finalCount = await counter.get()
            #expect(finalCount == 1)
        }
    }

    // MARK: - Test event handler

    @Test("RetryEventHandler receives correct error type")
    func eventHandlerTypedError() async throws {
        let errorCollector = ErrorCollector<TestError>()

        let handler = RetryEventHandler<TestError> { attempt, error, delay in
            await errorCollector.append(error)
        }

        do {
            _ = try await withRetry(
                configuration: RetryConfiguration(maxAttempts: 3, initialDelay: .milliseconds(1)),
                eventHandler: handler
            ) { () async throws(TestError) -> String in
                throw TestError.networkError
            }
        } catch {
            // Expected
        }

        let errorCount = await errorCollector.count()
        let allErrors = await errorCollector.getAll()
        #expect(errorCount == 2)  // 2 retries before final failure
        #expect(allErrors.allSatisfy { $0 == .networkError })
    }

    // MARK: - Test KeyedRateLimiter with generic type

    @Test("KeyedRateLimiter works with specific limiter type")
    func keyedRateLimiterGeneric() async throws {
        let keyedLimiter = KeyedRateLimiter<String, TokenBucketRateLimiter>(
            maxKeys: 10
        ) {
            TokenBucketRateLimiter(capacity: 5, refillRate: 5.0)
        }

        // Should work without any issues
        try await keyedLimiter.acquire(for: "user1")
        let canAcquire = await keyedLimiter.tryAcquire(for: "user1")
        #expect(canAcquire == true)
    }

    // MARK: - Test convenience overload

    @Test("Convenience withRetry overload works")
    func convenienceOverload() async throws {
        let counter = Counter()

        let result = try await withRetry(maxAttempts: 2, delay: .milliseconds(1)) {
            let attempt = await counter.increment()
            if attempt < 2 {
                throw TestError.failed
            }
            return 42
        }

        #expect(result == 42)
        let finalCount = await counter.get()
        #expect(finalCount == 2)
    }

    // MARK: - Test that standard library errors work

    @Test("withRetry works with standard library errors")
    func standardLibraryErrors() async throws {
        let counter = Counter()

        // Using CancellationError from standard library
        let result: String = try await withRetry(
            configuration: RetryConfiguration(maxAttempts: 3)
        ) {
            let attempt = await counter.increment()
            if attempt < 2 {
                throw CancellationError()
            }
            return "done"
        }

        #expect(result == "done")
    }

    // MARK: - Test non-throwing closure works

    @Test("withRetry works with non-throwing closure")
    func nonThrowingClosure() async throws {
        let counter = Counter()

        // A closure that never throws should work
        let result = try await withRetry(
            configuration: RetryConfiguration(maxAttempts: 3)
        ) {
            _ = await counter.increment()
            return "always succeeds"
        }

        #expect(result == "always succeeds")
        let finalCount = await counter.get()
        #expect(finalCount == 1)  // Only one attempt needed
    }

    // MARK: - Test with multiple rate limiter types

    @Test("withRetry works with different rate limiter types")
    func differentRateLimiterTypes() async throws {
        // Test with LeakyBucketRateLimiter
        let leakyLimiter = LeakyBucketRateLimiter(capacity: 10, leakRate: 10.0)

        let result1 = try await withRetry(
            configuration: RetryConfiguration(maxAttempts: 2),
            rateLimiter: leakyLimiter
        ) {
            return "leaky"
        }
        #expect(result1 == "leaky")

        // Test with FixedWindowRateLimiter
        let fixedLimiter = FixedWindowRateLimiter(limit: 10, window: .seconds(1))

        let result2 = try await withRetry(
            configuration: RetryConfiguration(maxAttempts: 2),
            rateLimiter: fixedLimiter
        ) {
            return "fixed"
        }
        #expect(result2 == "fixed")
    }

    // MARK: - Test CircuitBreaker with typed throws

    @Test("CircuitBreaker execute with typed throws works")
    func circuitBreakerTypedThrows() async throws {
        let breaker = CircuitBreaker(failureThreshold: 2, successThreshold: 1, timeout: .seconds(1))

        // First call succeeds
        let result = try await breaker.execute { () async throws(TestError) -> String in
            return "success"
        }
        #expect(result == "success")

        // Call that throws
        do {
            _ = try await breaker.execute { () async throws(TestError) -> String in
                throw TestError.networkError
            }
            Issue.record("Should have thrown")
        } catch let failure {
            switch failure {
            case .operationFailed(let error):
                #expect(error == .networkError)
            case .circuitOpen:
                Issue.record("Circuit should not be open yet")
            }
        }
    }

    // MARK: - Test withResilience

    @Test("withResilience combines rate limiter and retry")
    func withResilienceCombined() async throws {
        let limiter = TokenBucketRateLimiter(capacity: 10, refillRate: 10.0)
        let counter = Counter()

        let result = try await withResilience(
            rateLimiter: limiter,
            retryConfiguration: RetryConfiguration(maxAttempts: 3)
        ) {
            let attempt = await counter.increment()
            if attempt < 2 {
                throw TestError.failed
            }
            return "resilient"
        }

        #expect(result == "resilient")
    }
}
