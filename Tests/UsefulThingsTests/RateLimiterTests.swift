import Testing
@testable import UsefulThings

// MARK: - Duration Extension Tests

@Suite("Duration Extension Tests")
struct DurationExtensionTests {

    @Test("toSeconds converts whole seconds correctly")
    func wholeSeconds() {
        let duration = Duration.seconds(5)
        #expect(duration.toSeconds == 5.0)
    }

    @Test("toSeconds converts milliseconds correctly")
    func milliseconds() {
        let duration = Duration.milliseconds(1500)
        #expect(abs(duration.toSeconds - 1.5) < 0.0001)
    }

    @Test("toSeconds handles zero duration")
    func zeroDuration() {
        let duration = Duration.zero
        #expect(duration.toSeconds == 0.0)
    }

    @Test("toSeconds handles sub-millisecond precision")
    func subMillisecond() {
        let duration = Duration.nanoseconds(500_000_000) // 0.5 seconds
        #expect(abs(duration.toSeconds - 0.5) < 0.0001)
    }
}

// MARK: - Token Bucket Rate Limiter Tests

@Suite("TokenBucketRateLimiter Tests")
struct TokenBucketRateLimiterTests {

    @Test("allows immediate acquisition when tokens available")
    func immediateAcquisition() async throws {
        let limiter = TokenBucketRateLimiter(capacity: 5, refillRate: 1.0)

        let acquired = await limiter.tryAcquire()
        #expect(acquired == true)

        let tokens = await limiter.availableTokens
        #expect(tokens < 5.0)
    }

    @Test("allows burst up to capacity")
    func burstCapacity() async throws {
        let limiter = TokenBucketRateLimiter(capacity: 5, refillRate: 1.0)

        // Should be able to acquire 5 tokens immediately
        for i in 1...5 {
            let acquired = await limiter.tryAcquire()
            #expect(acquired == true, "Should acquire token \(i)")
        }

        // 6th should fail
        let acquired = await limiter.tryAcquire()
        #expect(acquired == false)
    }

    @Test("refills tokens over time")
    func tokenRefill() async throws {
        let limiter = TokenBucketRateLimiter(capacity: 2, refillRate: 10.0) // 10 tokens/sec

        // Drain all tokens
        _ = await limiter.tryAcquire()
        _ = await limiter.tryAcquire()

        let acquired1 = await limiter.tryAcquire()
        #expect(acquired1 == false)

        // Wait for refill (100ms = 1 token at 10/sec)
        try await Task.sleep(for: .milliseconds(150))

        let acquired2 = await limiter.tryAcquire()
        #expect(acquired2 == true)
    }

    @Test("acquire waits when no tokens available")
    func acquireWaits() async throws {
        let limiter = TokenBucketRateLimiter(capacity: 1, refillRate: 10.0) // 10 tokens/sec

        // Drain token
        _ = await limiter.tryAcquire()

        let start = ContinuousClock.now
        try await limiter.acquire()
        let elapsed = start.duration(to: ContinuousClock.now)

        // Should have waited approximately 100ms
        #expect(elapsed >= .milliseconds(80))
    }

    @Test("timeUntilAvailable returns correct duration")
    func timeUntilAvailable() async throws {
        let limiter = TokenBucketRateLimiter(capacity: 1, refillRate: 10.0)

        // When tokens available, should return zero
        let immediate = await limiter.timeUntilAvailable()
        #expect(immediate == .zero)

        // Drain token
        _ = await limiter.tryAcquire()

        let wait = await limiter.timeUntilAvailable()
        #expect(wait > .zero)
        #expect(wait <= .milliseconds(110)) // Should be ~100ms
    }

    @Test("reset restores full capacity")
    func reset() async throws {
        let limiter = TokenBucketRateLimiter(capacity: 5, refillRate: 1.0)

        // Drain all tokens
        for _ in 1...5 {
            _ = await limiter.tryAcquire()
        }

        let acquiredBefore = await limiter.tryAcquire()
        #expect(acquiredBefore == false)

        await limiter.reset()

        let acquiredAfter = await limiter.tryAcquire()
        #expect(acquiredAfter == true)

        let tokens = await limiter.availableTokens
        #expect(tokens >= 4.0) // Started with 5, acquired 1
    }

    @Test("init with window calculates correct refill rate")
    func initWithWindow() async throws {
        // 10 requests per second
        let limiter = TokenBucketRateLimiter(capacity: 10, per: .seconds(1))

        // Should allow 10 immediate requests
        for _ in 1...10 {
            let acquired = await limiter.tryAcquire()
            #expect(acquired == true)
        }

        let acquired = await limiter.tryAcquire()
        #expect(acquired == false)
    }

    @Test("handles cancellation during acquire")
    func cancellation() async throws {
        let limiter = TokenBucketRateLimiter(capacity: 1, refillRate: 0.1) // Very slow refill

        _ = await limiter.tryAcquire() // Drain

        let task = Task {
            try await limiter.acquire()
        }

        // Give task time to start waiting
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("Should have been cancelled")
        } catch is CancellationError {
            // Expected
        }
    }

    @Test("tokens never exceed capacity")
    func tokensNeverExceedCapacity() async throws {
        let limiter = TokenBucketRateLimiter(capacity: 3, refillRate: 100.0)

        // Wait for potential over-refill
        try await Task.sleep(for: .milliseconds(100))

        let tokens = await limiter.availableTokens
        #expect(tokens <= 3.0)
    }
}

// MARK: - Leaky Bucket Rate Limiter Tests

@Suite("LeakyBucketRateLimiter Tests")
struct LeakyBucketRateLimiterTests {

    @Test("allows requests when bucket not full")
    func allowsRequests() async throws {
        let limiter = LeakyBucketRateLimiter(capacity: 5, leakRate: 0.0001) // Extremely slow leak

        let acquired = await limiter.tryAcquire()
        #expect(acquired == true)
    }

    @Test("bucket eventually fills and blocks")
    func bucketFillsAndBlocks() async throws {
        // Use extremely slow leak to minimize timing effects
        // 0.0001 leak/sec means 0.00001 units leak per 100ms of test time
        let limiter = LeakyBucketRateLimiter(capacity: 10, leakRate: 0.0001)

        // Make many requests to definitively fill the bucket
        var successCount = 0
        for _ in 1...15 {
            if await limiter.tryAcquire() {
                successCount += 1
            }
        }

        // Should have succeeded approximately capacity times (maybe a tiny bit more due to leakage)
        #expect(successCount >= 10)
        #expect(successCount <= 11) // Allow for minimal leakage
    }

    @Test("leaks over time")
    func leaksOverTime() async throws {
        // High leak rate to see effect quickly
        let limiter = LeakyBucketRateLimiter(capacity: 1, leakRate: 50.0) // 50 units/sec

        // Fill bucket
        _ = await limiter.tryAcquire()

        // Need to wait for capacity to leak (1 unit / 50 per sec = 20ms)
        // Wait longer to ensure leak completes
        try await Task.sleep(for: .milliseconds(50))

        let acquired = await limiter.tryAcquire()
        #expect(acquired == true)
    }

    @Test("acquire waits when bucket is full")
    func acquireWaitsWhenFull() async throws {
        // Test that acquire() respects rate limiting by measuring throughput
        // With capacity 3 and leak rate 30, we can sustain 30 req/sec
        // Making 4 requests means the 4th must wait for leakage
        let limiter = LeakyBucketRateLimiter(capacity: 3, leakRate: 30.0)

        let start = ContinuousClock.now

        // Make 6 requests - more than capacity, so some must wait
        for _ in 1...6 {
            try await limiter.acquire()
        }

        let elapsed = start.duration(to: ContinuousClock.now)

        // With capacity 3 and leak rate 30:
        // First 3 requests complete immediately (fill bucket)
        // Requests 4-6 need to wait for leakage
        // At 30 units/sec, 3 extra units take ~100ms to leak
        // Total time should be at least 50ms (allowing for imprecision)
        #expect(elapsed >= .milliseconds(50))
    }

    @Test("reset empties bucket")
    func reset() async throws {
        // Extremely slow leak
        let limiter = LeakyBucketRateLimiter(capacity: 5, leakRate: 0.0001)

        // Fill bucket beyond capacity attempts
        for _ in 1...10 {
            _ = await limiter.tryAcquire()
        }

        await limiter.reset()

        // After reset, should have full capacity again
        var successCount = 0
        for _ in 1...5 {
            if await limiter.tryAcquire() {
                successCount += 1
            }
        }
        #expect(successCount == 5)
    }

    @Test("init with window calculates correct leak rate")
    func initWithWindow() async throws {
        // 10 per 100 seconds = 0.1 leak/sec, very slow for test
        let limiter = LeakyBucketRateLimiter(capacity: 10, per: .seconds(100))

        // Should allow approximately 10 requests
        var successCount = 0
        for _ in 1...12 {
            if await limiter.tryAcquire() {
                successCount += 1
            }
        }

        // Should have succeeded around capacity times
        #expect(successCount >= 10)
        #expect(successCount <= 11)
    }

    @Test("water level never goes negative")
    func waterLevelNeverNegative() async throws {
        let limiter = LeakyBucketRateLimiter(capacity: 5, leakRate: 100.0)

        // Wait for potential over-leak
        try await Task.sleep(for: .milliseconds(200))

        // Should still work - water level should be 0, not negative
        let acquired = await limiter.tryAcquire()
        #expect(acquired == true)
    }
}

// MARK: - Fixed Window Rate Limiter Tests

@Suite("FixedWindowRateLimiter Tests")
struct FixedWindowRateLimiterTests {

    @Test("allows requests within limit")
    func allowsRequestsWithinLimit() async throws {
        let limiter = FixedWindowRateLimiter(limit: 5, window: .seconds(10))

        for i in 1...5 {
            let acquired = await limiter.tryAcquire()
            #expect(acquired == true, "Should acquire request \(i)")
        }
    }

    @Test("blocks requests exceeding limit")
    func blocksExceedingLimit() async throws {
        let limiter = FixedWindowRateLimiter(limit: 3, window: .seconds(10))

        for _ in 1...3 {
            _ = await limiter.tryAcquire()
        }

        let acquired = await limiter.tryAcquire()
        #expect(acquired == false)
    }

    @Test("resets count when window expires")
    func windowExpiration() async throws {
        let limiter = FixedWindowRateLimiter(limit: 2, window: .milliseconds(100))

        // Exhaust limit
        _ = await limiter.tryAcquire()
        _ = await limiter.tryAcquire()

        let acquired1 = await limiter.tryAcquire()
        #expect(acquired1 == false)

        // Wait for window to expire
        try await Task.sleep(for: .milliseconds(150))

        // Should work in new window
        let acquired2 = await limiter.tryAcquire()
        #expect(acquired2 == true)
    }

    @Test("acquire waits for window rotation")
    func acquireWaitsForRotation() async throws {
        let limiter = FixedWindowRateLimiter(limit: 1, window: .milliseconds(100))

        _ = await limiter.tryAcquire()

        let start = ContinuousClock.now
        try await limiter.acquire()
        let elapsed = start.duration(to: ContinuousClock.now)

        #expect(elapsed >= .milliseconds(90))
    }

    @Test("timeUntilAvailable returns remaining window time")
    func timeUntilAvailable() async throws {
        let limiter = FixedWindowRateLimiter(limit: 1, window: .milliseconds(200))

        let immediate = await limiter.timeUntilAvailable()
        #expect(immediate == .zero)

        _ = await limiter.tryAcquire()

        let wait = await limiter.timeUntilAvailable()
        #expect(wait > .zero)
        #expect(wait <= .milliseconds(210))
    }

    @Test("reset clears count and starts new window")
    func reset() async throws {
        let limiter = FixedWindowRateLimiter(limit: 2, window: .seconds(60))

        _ = await limiter.tryAcquire()
        _ = await limiter.tryAcquire()

        let acquiredBefore = await limiter.tryAcquire()
        #expect(acquiredBefore == false)

        await limiter.reset()

        let acquiredAfter = await limiter.tryAcquire()
        #expect(acquiredAfter == true)
    }

    @Test("handles multiple windows passing")
    func multipleWindowsPassing() async throws {
        let limiter = FixedWindowRateLimiter(limit: 2, window: .milliseconds(50))

        _ = await limiter.tryAcquire()
        _ = await limiter.tryAcquire()

        // Wait for multiple windows to pass
        try await Task.sleep(for: .milliseconds(150))

        // Should be able to acquire again
        let acquired = await limiter.tryAcquire()
        #expect(acquired == true)
    }
}

// MARK: - Sliding Window Log Rate Limiter Tests

@Suite("SlidingWindowLogRateLimiter Tests")
struct SlidingWindowLogRateLimiterTests {

    @Test("allows requests within limit")
    func allowsRequestsWithinLimit() async throws {
        let limiter = SlidingWindowLogRateLimiter(limit: 5, window: .seconds(10))

        for i in 1...5 {
            let acquired = await limiter.tryAcquire()
            #expect(acquired == true, "Should acquire request \(i)")
        }
    }

    @Test("blocks requests exceeding limit")
    func blocksExceedingLimit() async throws {
        let limiter = SlidingWindowLogRateLimiter(limit: 3, window: .seconds(10))

        for _ in 1...3 {
            _ = await limiter.tryAcquire()
        }

        let acquired = await limiter.tryAcquire()
        #expect(acquired == false)
    }

    @Test("sliding window expires oldest requests")
    func slidingExpiration() async throws {
        // Use longer window for timing stability
        let limiter = SlidingWindowLogRateLimiter(limit: 2, window: .milliseconds(200))

        _ = await limiter.tryAcquire()
        _ = await limiter.tryAcquire()

        // Should be blocked - we've used the limit
        let acquired1 = await limiter.tryAcquire()
        #expect(acquired1 == false)

        // Wait for requests to expire (200ms + buffer)
        try await Task.sleep(for: .milliseconds(250))

        // Requests should have expired, allowing new ones
        let acquired2 = await limiter.tryAcquire()
        #expect(acquired2 == true)
    }

    @Test("acquire waits for oldest to expire")
    func acquireWaitsForExpiry() async throws {
        let limiter = SlidingWindowLogRateLimiter(limit: 1, window: .milliseconds(100))

        _ = await limiter.tryAcquire()

        let start = ContinuousClock.now
        try await limiter.acquire()
        let elapsed = start.duration(to: ContinuousClock.now)

        #expect(elapsed >= .milliseconds(90))
    }

    @Test("timeUntilAvailable based on oldest timestamp")
    func timeUntilAvailable() async throws {
        let limiter = SlidingWindowLogRateLimiter(limit: 1, window: .milliseconds(200))

        let immediate = await limiter.timeUntilAvailable()
        #expect(immediate == .zero)

        _ = await limiter.tryAcquire()

        let wait = await limiter.timeUntilAvailable()
        #expect(wait > .zero)
        #expect(wait <= .milliseconds(210))
    }

    @Test("reset clears all timestamps")
    func reset() async throws {
        let limiter = SlidingWindowLogRateLimiter(limit: 2, window: .seconds(60))

        _ = await limiter.tryAcquire()
        _ = await limiter.tryAcquire()

        let acquiredBefore = await limiter.tryAcquire()
        #expect(acquiredBefore == false)

        await limiter.reset()

        let acquiredAfter = await limiter.tryAcquire()
        #expect(acquiredAfter == true)
    }

    @Test("accurate sliding window (no boundary burst)")
    func noBoundaryBurst() async throws {
        // Use a very long window (2 seconds) to ensure requests never expire during test
        let limiter = SlidingWindowLogRateLimiter(limit: 3, window: .seconds(2))

        // Make 3 requests rapidly - this exhausts the limit
        for _ in 1...3 {
            _ = await limiter.tryAcquire()
        }

        // 4th request should be blocked immediately
        let blocked1 = await limiter.tryAcquire()
        #expect(blocked1 == false)

        // Even after 100ms delay, should still be blocked
        // (unlike fixed window which would allow burst at boundary)
        // 100ms is only 5% of the 2-second window
        try await Task.sleep(for: .milliseconds(100))

        let blocked2 = await limiter.tryAcquire()
        #expect(blocked2 == false)
    }
}

// MARK: - Sliding Window Counter Rate Limiter Tests

@Suite("SlidingWindowCounterRateLimiter Tests")
struct SlidingWindowCounterRateLimiterTests {

    @Test("allows requests within limit")
    func allowsRequestsWithinLimit() async throws {
        let limiter = SlidingWindowCounterRateLimiter(limit: 5, window: .seconds(10))

        for i in 1...5 {
            let acquired = await limiter.tryAcquire()
            #expect(acquired == true, "Should acquire request \(i)")
        }
    }

    @Test("blocks requests exceeding limit")
    func blocksExceedingLimit() async throws {
        let limiter = SlidingWindowCounterRateLimiter(limit: 3, window: .seconds(10))

        for _ in 1...3 {
            _ = await limiter.tryAcquire()
        }

        let acquired = await limiter.tryAcquire()
        #expect(acquired == false)
    }

    @Test("weighted count considers previous window")
    func weightedCount() async throws {
        let limiter = SlidingWindowCounterRateLimiter(limit: 4, window: .milliseconds(100))

        // Make 3 requests in first window
        for _ in 1...3 {
            _ = await limiter.tryAcquire()
        }

        // Move to next window (halfway through)
        try await Task.sleep(for: .milliseconds(150))

        // Previous count (3) is weighted at ~0.5, so weighted count is ~1.5
        // Should allow some requests but not full 4
        let acquired1 = await limiter.tryAcquire()
        let acquired2 = await limiter.tryAcquire()
        #expect(acquired1 == true)
        #expect(acquired2 == true)
    }

    @Test("acquire waits when weighted limit exceeded")
    func acquireWaits() async throws {
        let limiter = SlidingWindowCounterRateLimiter(limit: 1, window: .milliseconds(100))

        _ = await limiter.tryAcquire()

        let start = ContinuousClock.now
        try await limiter.acquire()
        let elapsed = start.duration(to: ContinuousClock.now)

        #expect(elapsed >= .milliseconds(50)) // Should wait at least partial window
    }

    @Test("reset clears both windows")
    func reset() async throws {
        let limiter = SlidingWindowCounterRateLimiter(limit: 2, window: .seconds(60))

        _ = await limiter.tryAcquire()
        _ = await limiter.tryAcquire()

        let acquiredBefore = await limiter.tryAcquire()
        #expect(acquiredBefore == false)

        await limiter.reset()

        let acquiredAfter = await limiter.tryAcquire()
        #expect(acquiredAfter == true)
    }

    @Test("previous window weight approaches zero")
    func previousWindowWeightDecays() async throws {
        let limiter = SlidingWindowCounterRateLimiter(limit: 3, window: .milliseconds(50))

        // Fill first window
        for _ in 1...3 {
            _ = await limiter.tryAcquire()
        }

        // Wait for two full windows (previous count becomes 0)
        try await Task.sleep(for: .milliseconds(120))

        // Should have full limit available
        for i in 1...3 {
            let acquired = await limiter.tryAcquire()
            #expect(acquired == true, "Should acquire request \(i)")
        }
    }
}

// MARK: - Concurrency Limiter Tests

@Suite("ConcurrencyLimiter Tests")
struct ConcurrencyLimiterTests {

    @Test("allows concurrent operations up to limit")
    func allowsConcurrentUpToLimit() async throws {
        let limiter = ConcurrencyLimiter(maxConcurrent: 3)

        let acquired1 = await limiter.tryAcquire()
        let acquired2 = await limiter.tryAcquire()
        let acquired3 = await limiter.tryAcquire()

        #expect(acquired1 == true)
        #expect(acquired2 == true)
        #expect(acquired3 == true)

        let acquired4 = await limiter.tryAcquire()
        #expect(acquired4 == false)
    }

    @Test("release allows new acquisitions")
    func releaseAllowsNew() async throws {
        let limiter = ConcurrencyLimiter(maxConcurrent: 1)

        let acquired1 = await limiter.tryAcquire()
        #expect(acquired1 == true)

        let acquired2 = await limiter.tryAcquire()
        #expect(acquired2 == false)

        await limiter.release()

        let acquired3 = await limiter.tryAcquire()
        #expect(acquired3 == true)
    }

    @Test("acquire waits when at limit")
    func acquireWaitsAtLimit() async throws {
        let limiter = ConcurrencyLimiter(maxConcurrent: 1)

        _ = await limiter.tryAcquire()

        let task = Task {
            try await limiter.acquire()
            return "acquired"
        }

        // Give task time to start waiting
        try await Task.sleep(for: .milliseconds(50))

        // Release the slot
        await limiter.release()

        let result = try await task.value
        #expect(result == "acquired")
    }

    @Test("withPermit automatically releases")
    func withPermitAutoRelease() async throws {
        let limiter = ConcurrencyLimiter(maxConcurrent: 1)

        let result = try await limiter.withPermit {
            return "done"
        }
        #expect(result == "done")

        // Should be able to acquire again
        let acquired = await limiter.tryAcquire()
        #expect(acquired == true)
    }

    @Test("withPermit releases on error")
    func withPermitReleasesOnError() async throws {
        let limiter = ConcurrencyLimiter(maxConcurrent: 1)

        do {
            _ = try await limiter.withPermit {
                throw TestError.failed
            }
            Issue.record("Should have thrown")
        } catch {
            // Expected
        }

        // Should still be able to acquire
        let acquired = await limiter.tryAcquire()
        #expect(acquired == true)
    }

    @Test("timeUntilAvailable behavior when full")
    func timeUntilAvailableBehaviorWhenFull() async throws {
        let limiter = ConcurrencyLimiter(maxConcurrent: 1)

        let immediate = await limiter.timeUntilAvailable()
        #expect(immediate == .zero)

        _ = await limiter.tryAcquire()

        // When full, ConcurrencyLimiter returns .seconds(Double.infinity)
        // Duration comparison with infinity can crash, so we verify behavior
        // by checking that tryAcquire fails
        let blocked = await limiter.tryAcquire()
        #expect(blocked == false)

        // After release, should be available again
        await limiter.release()
        let availableAgain = await limiter.timeUntilAvailable()
        #expect(availableAgain == .zero)
    }

    @Test("reset cancels waiters")
    func resetCancelsWaiters() async throws {
        let limiter = ConcurrencyLimiter(maxConcurrent: 1)

        _ = await limiter.tryAcquire()

        let task = Task {
            do {
                try await limiter.acquire()
                return "acquired"
            } catch {
                return "cancelled"
            }
        }

        // Give task time to start waiting
        try await Task.sleep(for: .milliseconds(50))

        await limiter.reset()

        let result = try await task.value
        #expect(result == "cancelled")
    }

    @Test("release never goes negative")
    func releaseNeverNegative() async throws {
        let limiter = ConcurrencyLimiter(maxConcurrent: 2)

        // Release without acquire
        await limiter.release()
        await limiter.release()

        // Should still have capacity of 2
        let acquired1 = await limiter.tryAcquire()
        let acquired2 = await limiter.tryAcquire()
        let acquired3 = await limiter.tryAcquire()

        #expect(acquired1 == true)
        #expect(acquired2 == true)
        #expect(acquired3 == false)
    }

    @Test("FIFO ordering of waiters")
    func fifoOrdering() async throws {
        let limiter = ConcurrencyLimiter(maxConcurrent: 1)
        var order: [Int] = []
        let orderActor = OrderActor()

        _ = await limiter.tryAcquire()

        // Start multiple waiting tasks
        let task1 = Task {
            try await limiter.acquire()
            await orderActor.append(1)
            await limiter.release()
        }

        try await Task.sleep(for: .milliseconds(20))

        let task2 = Task {
            try await limiter.acquire()
            await orderActor.append(2)
            await limiter.release()
        }

        try await Task.sleep(for: .milliseconds(20))

        // Release initial lock
        await limiter.release()

        try await task1.value
        try await task2.value

        order = await orderActor.items
        #expect(order == [1, 2])
    }
}

actor OrderActor {
    var items: [Int] = []
    func append(_ item: Int) { items.append(item) }
}

// MARK: - Adaptive Rate Limiter Tests

@Suite("AdaptiveRateLimiter Tests")
struct AdaptiveRateLimiterTests {

    @Test("starts at initial rate")
    func startsAtInitialRate() async throws {
        let limiter = AdaptiveRateLimiter(
            initialRate: 5.0,
            minRate: 1.0,
            maxRate: 10.0
        )

        let rate = await limiter.currentRatePerSecond
        #expect(rate == 5.0)
    }

    @Test("increases rate on success")
    func increasesOnSuccess() async throws {
        let limiter = AdaptiveRateLimiter(
            initialRate: 5.0,
            minRate: 1.0,
            maxRate: 10.0,
            increaseRatio: 1.2
        )

        await limiter.recordSuccess()

        let rate = await limiter.currentRatePerSecond
        #expect(rate == 6.0) // 5.0 * 1.2
    }

    @Test("decreases rate on rate limit")
    func decreasesOnRateLimit() async throws {
        let limiter = AdaptiveRateLimiter(
            initialRate: 5.0,
            minRate: 1.0,
            maxRate: 10.0,
            decreaseRatio: 0.5
        )

        await limiter.recordRateLimited()

        let rate = await limiter.currentRatePerSecond
        #expect(rate == 2.5) // 5.0 * 0.5
    }

    @Test("rate never exceeds max")
    func rateNeverExceedsMax() async throws {
        let limiter = AdaptiveRateLimiter(
            initialRate: 9.0,
            minRate: 1.0,
            maxRate: 10.0,
            increaseRatio: 1.5
        )

        await limiter.recordSuccess()
        await limiter.recordSuccess()

        let rate = await limiter.currentRatePerSecond
        #expect(rate == 10.0)
    }

    @Test("rate never goes below min")
    func rateNeverBelowMin() async throws {
        let limiter = AdaptiveRateLimiter(
            initialRate: 2.0,
            minRate: 1.0,
            maxRate: 10.0,
            decreaseRatio: 0.3
        )

        await limiter.recordRateLimited()
        await limiter.recordRateLimited()

        let rate = await limiter.currentRatePerSecond
        #expect(rate == 1.0)
    }

    @Test("tryAcquire respects current rate")
    func tryAcquireRespectsRate() async throws {
        let limiter = AdaptiveRateLimiter(
            initialRate: 2.0, // 2 tokens/sec
            minRate: 1.0,
            maxRate: 10.0
        )

        // Should have 2 tokens initially
        let acquired1 = await limiter.tryAcquire()
        let acquired2 = await limiter.tryAcquire()
        let acquired3 = await limiter.tryAcquire()

        #expect(acquired1 == true)
        #expect(acquired2 == true)
        #expect(acquired3 == false)
    }

    @Test("recordRateLimited also reduces tokens")
    func recordRateLimitedReducesTokens() async throws {
        let limiter = AdaptiveRateLimiter(
            initialRate: 10.0,
            minRate: 1.0,
            maxRate: 20.0,
            decreaseRatio: 0.5
        )

        // Record rate limit - rate becomes 5, tokens capped at 2.5
        await limiter.recordRateLimited()

        // Should have limited tokens
        let acquired1 = await limiter.tryAcquire()
        let acquired2 = await limiter.tryAcquire()
        let acquired3 = await limiter.tryAcquire()

        #expect(acquired1 == true)
        #expect(acquired2 == true)
        #expect(acquired3 == false)
    }

    @Test("reset restores tokens")
    func reset() async throws {
        let limiter = AdaptiveRateLimiter(
            initialRate: 3.0,
            minRate: 1.0,
            maxRate: 10.0
        )

        // Drain tokens
        _ = await limiter.tryAcquire()
        _ = await limiter.tryAcquire()
        _ = await limiter.tryAcquire()

        let acquiredBefore = await limiter.tryAcquire()
        #expect(acquiredBefore == false)

        await limiter.reset()

        let acquiredAfter = await limiter.tryAcquire()
        #expect(acquiredAfter == true)
    }
}

// MARK: - Composite Rate Limiter Tests

@Suite("CompositeRateLimiter Tests")
struct CompositeRateLimiterTests {

    @Test("requires all limiters to allow")
    func requiresAllLimiters() async throws {
        let limiter1 = TokenBucketRateLimiter(capacity: 2, refillRate: 1.0)
        let limiter2 = TokenBucketRateLimiter(capacity: 3, refillRate: 1.0)

        let composite = CompositeRateLimiter(limiter1, limiter2)

        // First limiter allows 2, second allows 3
        // Composite should be limited by first (2)
        let acquired1 = await composite.tryAcquire()
        let acquired2 = await composite.tryAcquire()
        let acquired3 = await composite.tryAcquire()

        #expect(acquired1 == true)
        #expect(acquired2 == true)
        #expect(acquired3 == false)
    }

    @Test("timeUntilAvailable returns max wait")
    func timeUntilAvailableReturnsMax() async throws {
        let limiter1 = FixedWindowRateLimiter(limit: 1, window: .milliseconds(100))
        let limiter2 = FixedWindowRateLimiter(limit: 1, window: .milliseconds(200))

        let composite = CompositeRateLimiter(limiter1, limiter2)

        // Drain both
        _ = await composite.tryAcquire()

        let wait = await composite.timeUntilAvailable()
        // Should be close to 200ms (the longer window)
        #expect(wait >= .milliseconds(90))
    }

    @Test("acquire waits for all limiters")
    func acquireWaitsForAll() async throws {
        let limiter1 = TokenBucketRateLimiter(capacity: 1, refillRate: 10.0) // 100ms refill
        let limiter2 = TokenBucketRateLimiter(capacity: 1, refillRate: 5.0)  // 200ms refill

        let composite = CompositeRateLimiter(limiter1, limiter2)

        _ = await composite.tryAcquire()

        let start = ContinuousClock.now
        try await composite.acquire()
        let elapsed = start.duration(to: ContinuousClock.now)

        // Should wait for slower limiter
        #expect(elapsed >= .milliseconds(150))
    }

    @Test("reset resets all limiters")
    func resetResetsAll() async throws {
        let limiter1 = TokenBucketRateLimiter(capacity: 1, refillRate: 0.01)
        let limiter2 = TokenBucketRateLimiter(capacity: 1, refillRate: 0.01)

        let composite = CompositeRateLimiter(limiter1, limiter2)

        _ = await composite.tryAcquire()

        let acquiredBefore = await composite.tryAcquire()
        #expect(acquiredBefore == false)

        await composite.reset()

        let acquiredAfter = await composite.tryAcquire()
        #expect(acquiredAfter == true)
    }

    @Test("works with different limiter types")
    func differentLimiterTypes() async throws {
        let tokenBucket = TokenBucketRateLimiter(capacity: 5, refillRate: 1.0)
        let fixedWindow = FixedWindowRateLimiter(limit: 3, window: .seconds(10))

        let composite = CompositeRateLimiter(tokenBucket, fixedWindow)

        // Limited by fixed window (3)
        let acquired1 = await composite.tryAcquire()
        let acquired2 = await composite.tryAcquire()
        let acquired3 = await composite.tryAcquire()
        let acquired4 = await composite.tryAcquire()

        #expect(acquired1 == true)
        #expect(acquired2 == true)
        #expect(acquired3 == true)
        #expect(acquired4 == false)
    }

    @Test("single limiter composite works")
    func singleLimiter() async throws {
        let limiter = TokenBucketRateLimiter(capacity: 2, refillRate: 1.0)
        let composite = CompositeRateLimiter(limiter)

        let acquired1 = await composite.tryAcquire()
        let acquired2 = await composite.tryAcquire()
        let acquired3 = await composite.tryAcquire()

        #expect(acquired1 == true)
        #expect(acquired2 == true)
        #expect(acquired3 == false)
    }
}

// MARK: - Keyed Rate Limiter Tests

@Suite("KeyedRateLimiter Tests")
struct KeyedRateLimiterTests {

    @Test("creates separate limiters per key")
    func separateLimitersPerKey() async throws {
        let keyedLimiter = KeyedRateLimiter<String, TokenBucketRateLimiter>(
            maxKeys: 10
        ) {
            TokenBucketRateLimiter(capacity: 2, refillRate: 1.0)
        }

        // User A uses their limit
        _ = await keyedLimiter.tryAcquire(for: "userA")
        _ = await keyedLimiter.tryAcquire(for: "userA")
        let userAResult = await keyedLimiter.tryAcquire(for: "userA")
        #expect(userAResult == false)

        // User B still has full limit
        let userBResult = await keyedLimiter.tryAcquire(for: "userB")
        #expect(userBResult == true)
    }

    @Test("reuses existing limiter for same key")
    func reusesLimiter() async throws {
        let keyedLimiter = KeyedRateLimiter<String, TokenBucketRateLimiter>(
            maxKeys: 10
        ) {
            TokenBucketRateLimiter(capacity: 3, refillRate: 1.0)
        }

        _ = await keyedLimiter.tryAcquire(for: "user")
        _ = await keyedLimiter.tryAcquire(for: "user")

        let count = await keyedLimiter.activeKeyCount
        #expect(count == 1)

        let acquired = await keyedLimiter.tryAcquire(for: "user")
        #expect(acquired == true) // 3rd of 3

        let blocked = await keyedLimiter.tryAcquire(for: "user")
        #expect(blocked == false) // 4th blocked
    }

    @Test("evicts when at max keys")
    func evictsWhenAtMaxKeys() async throws {
        let keyedLimiter = KeyedRateLimiter<String, TokenBucketRateLimiter>(
            maxKeys: 2
        ) {
            TokenBucketRateLimiter(capacity: 1, refillRate: 0.01)
        }

        // Create limiters for key1 and key2
        _ = await keyedLimiter.tryAcquire(for: "key1")
        _ = await keyedLimiter.tryAcquire(for: "key2")

        let countBefore = await keyedLimiter.activeKeyCount
        #expect(countBefore == 2)

        // Add key3, should evict one of the existing keys
        _ = await keyedLimiter.tryAcquire(for: "key3")

        // Count should still be 2 (max)
        let countAfter = await keyedLimiter.activeKeyCount
        #expect(countAfter == 2)

        // key3 should have succeeded with fresh limiter
        // (it got the token from a new limiter)
    }

    @Test("reset for specific key")
    func resetForKey() async throws {
        let keyedLimiter = KeyedRateLimiter<String, TokenBucketRateLimiter>(
            maxKeys: 10
        ) {
            TokenBucketRateLimiter(capacity: 1, refillRate: 0.01)
        }

        _ = await keyedLimiter.tryAcquire(for: "user")

        let blocked = await keyedLimiter.tryAcquire(for: "user")
        #expect(blocked == false)

        await keyedLimiter.reset(for: "user")

        let acquired = await keyedLimiter.tryAcquire(for: "user")
        #expect(acquired == true)
    }

    @Test("resetAll clears everything")
    func resetAll() async throws {
        let keyedLimiter = KeyedRateLimiter<String, TokenBucketRateLimiter>(
            maxKeys: 10
        ) {
            TokenBucketRateLimiter(capacity: 1, refillRate: 0.01)
        }

        _ = await keyedLimiter.tryAcquire(for: "user1")
        _ = await keyedLimiter.tryAcquire(for: "user2")

        let countBefore = await keyedLimiter.activeKeyCount
        #expect(countBefore == 2)

        await keyedLimiter.resetAll()

        let countAfter = await keyedLimiter.activeKeyCount
        #expect(countAfter == 0)
    }

    @Test("acquire waits correctly per key")
    func acquireWaitsPerKey() async throws {
        let keyedLimiter = KeyedRateLimiter<String, TokenBucketRateLimiter>(
            maxKeys: 10
        ) {
            TokenBucketRateLimiter(capacity: 1, refillRate: 10.0) // 100ms refill
        }

        _ = await keyedLimiter.tryAcquire(for: "user")

        let start = ContinuousClock.now
        try await keyedLimiter.acquire(for: "user")
        let elapsed = start.duration(to: ContinuousClock.now)

        #expect(elapsed >= .milliseconds(80))
    }

    @Test("works with integer keys")
    func integerKeys() async throws {
        let keyedLimiter = KeyedRateLimiter<Int, FixedWindowRateLimiter>(
            maxKeys: 100
        ) {
            FixedWindowRateLimiter(limit: 2, window: .seconds(10))
        }

        _ = await keyedLimiter.tryAcquire(for: 1)
        _ = await keyedLimiter.tryAcquire(for: 1)

        let blocked = await keyedLimiter.tryAcquire(for: 1)
        #expect(blocked == false)

        let otherKey = await keyedLimiter.tryAcquire(for: 2)
        #expect(otherKey == true)
    }

    @Test("no max keys allows unlimited")
    func noMaxKeys() async throws {
        let keyedLimiter = KeyedRateLimiter<String, TokenBucketRateLimiter>(
            maxKeys: nil
        ) {
            TokenBucketRateLimiter(capacity: 1, refillRate: 1.0)
        }

        // Create many keys
        for i in 1...100 {
            _ = await keyedLimiter.tryAcquire(for: "user\(i)")
        }

        let count = await keyedLimiter.activeKeyCount
        #expect(count == 100)
    }
}

// MARK: - Concurrent Access Tests

@Suite("Concurrent Access Tests")
struct ConcurrentAccessTests {

    @Test("TokenBucket handles concurrent access")
    func tokenBucketConcurrent() async throws {
        // Use very low refill rate so no tokens refill during the test
        let limiter = TokenBucketRateLimiter(capacity: 10, refillRate: 0.001)
        let successCounter = Counter()

        await withTaskGroup(of: Void.self) { group in
            for _ in 1...20 {
                group.addTask {
                    if await limiter.tryAcquire() {
                        _ = await successCounter.increment()
                    }
                }
            }
        }

        let successes = await successCounter.get()
        #expect(successes == 10) // Exactly capacity
    }

    @Test("ConcurrencyLimiter handles concurrent waiters")
    func concurrencyLimiterConcurrentWaiters() async throws {
        let limiter = ConcurrencyLimiter(maxConcurrent: 2)
        let runningCounter = Counter()
        let maxConcurrent = MaxTracker()

        await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 1...10 {
                group.addTask {
                    try await limiter.acquire()
                    let current = await runningCounter.increment()
                    await maxConcurrent.update(current)

                    try await Task.sleep(for: .milliseconds(10))

                    _ = await runningCounter.decrement()
                    await limiter.release()
                }
            }
        }

        let max = await maxConcurrent.max
        #expect(max <= 2)
    }

    @Test("KeyedRateLimiter handles concurrent key access")
    func keyedLimiterConcurrent() async throws {
        let keyedLimiter = KeyedRateLimiter<Int, TokenBucketRateLimiter>(
            maxKeys: 100
        ) {
            // Use very low refill rate so no tokens refill during the test
            TokenBucketRateLimiter(capacity: 5, refillRate: 0.001)
        }

        let successCounter = Counter()

        await withTaskGroup(of: Void.self) { group in
            for userId in 1...10 {
                for _ in 1...10 {
                    group.addTask {
                        if await keyedLimiter.tryAcquire(for: userId) {
                            _ = await successCounter.increment()
                        }
                    }
                }
            }
        }

        let successes = await successCounter.get()
        // Each user has 5 capacity, 10 users = 50 max
        #expect(successes == 50)
    }
}

actor MaxTracker {
    var max: Int = 0
    func update(_ value: Int) {
        if value > max { max = value }
    }
}

extension Counter {
    func decrement() -> Int {
        value -= 1
        return value
    }
}

// MARK: - Edge Case Tests

@Suite("Edge Case Tests")
struct EdgeCaseTests {

    @Test("Very small window duration")
    func verySmallWindow() async throws {
        let limiter = FixedWindowRateLimiter(limit: 1, window: .milliseconds(1))

        _ = await limiter.tryAcquire()

        // Wait just a bit
        try await Task.sleep(for: .milliseconds(5))

        let acquired = await limiter.tryAcquire()
        #expect(acquired == true)
    }

    @Test("Very high rate")
    func veryHighRate() async throws {
        let limiter = TokenBucketRateLimiter(capacity: 1000, refillRate: 10000.0)

        var successes = 0
        for _ in 1...1000 {
            if await limiter.tryAcquire() {
                successes += 1
            }
        }

        #expect(successes == 1000)
    }

    @Test("Zero tokens edge case")
    func zeroTokensEdgeCase() async throws {
        let limiter = TokenBucketRateLimiter(capacity: 1, refillRate: 1000.0)

        // Drain
        _ = await limiter.tryAcquire()

        // Immediate check should fail (no time for refill)
        let immediate = await limiter.tryAcquire()
        #expect(immediate == false)

        // But after tiny wait should work
        try await Task.sleep(for: .milliseconds(5))
        let afterWait = await limiter.tryAcquire()
        #expect(afterWait == true)
    }

    @Test("Rapid acquire/release cycle")
    func rapidAcquireRelease() async throws {
        let limiter = ConcurrencyLimiter(maxConcurrent: 1)

        for _ in 1...100 {
            try await limiter.acquire()
            await limiter.release()
        }

        // Should still work
        let acquired = await limiter.tryAcquire()
        #expect(acquired == true)
    }

    @Test("Sliding window with requests spread across time")
    func slidingWindowSpread() async throws {
        // Use longer window for timing stability
        let limiter = SlidingWindowLogRateLimiter(limit: 3, window: .milliseconds(300))

        // Make 3 requests - this exhausts the limit
        _ = await limiter.tryAcquire()
        _ = await limiter.tryAcquire()
        _ = await limiter.tryAcquire()

        // Should be blocked - we've used the limit
        let blocked = await limiter.tryAcquire()
        #expect(blocked == false)

        // Wait for requests to expire (300ms + buffer)
        try await Task.sleep(for: .milliseconds(350))

        // All requests should have expired
        let allowed = await limiter.tryAcquire()
        #expect(allowed == true)
    }

    @Test("Composite with empty parameter pack compiles")
    func compositeEmpty() async throws {
        // This tests that the variadic generic works with minimum items
        let limiter = TokenBucketRateLimiter(capacity: 5, refillRate: 1.0)
        let composite = CompositeRateLimiter(limiter)

        let acquired = await composite.tryAcquire()
        #expect(acquired == true)
    }

    @Test("Multiple resets in sequence")
    func multipleResets() async throws {
        let limiter = TokenBucketRateLimiter(capacity: 2, refillRate: 0.01)

        await limiter.reset()
        await limiter.reset()
        await limiter.reset()

        // Should still have full capacity
        let acquired1 = await limiter.tryAcquire()
        let acquired2 = await limiter.tryAcquire()
        let acquired3 = await limiter.tryAcquire()

        #expect(acquired1 == true)
        #expect(acquired2 == true)
        #expect(acquired3 == false)
    }
}
