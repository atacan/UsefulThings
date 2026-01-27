// MARK: - Duration Extension

extension Duration {
    /// Converts Duration to seconds as Double
    var toSeconds: Double {
        let (seconds, attoseconds) = self.components
        return Double(seconds) + Double(attoseconds) * 1e-18
    }
}

// MARK: - Errors

public enum RateLimiterError: Error, Sendable {
    case rateLimitExceeded
    case timeout
}

public struct RetryError: Error, Sendable {
    public let attempts: Int
    public let lastError: any Error
    public let allErrors: [any Error]
    
    public var description: String {
        "Failed after \(attempts) attempts. Last error: \(lastError)"
    }
}

// MARK: - Rate Limiter Protocol

/// Protocol for all rate limiters
/// Methods are async to support cross-actor calls in composite limiters
public protocol RateLimiter: Actor, Sendable {
    /// Acquires a permit, waiting if necessary until one is available
    func acquire() async throws
    
    /// Attempts to acquire a permit immediately without waiting
    /// Returns true if successful, false if rate limited
    func tryAcquire() async -> Bool
    
    /// Returns the estimated time until next permit is available
    func timeUntilAvailable() async -> Duration
    
    /// Resets the rate limiter to its initial state
    func reset() async
}

// MARK: - Token Bucket Rate Limiter

/// Token Bucket Algorithm
/// - Tokens accumulate over time up to a maximum capacity
/// - Each request consumes one token
/// - Allows bursts up to bucket capacity
/// - Best for: APIs that allow occasional burst traffic
public actor TokenBucketRateLimiter: RateLimiter {
    private let capacity: Double
    /// tokens per second
    private let refillRate: Double 
    private var tokens: Double
    private var lastRefillTime: ContinuousClock.Instant
    private let clock = ContinuousClock()
    
    /// Initialize with explicit refill rate
    public init(capacity: Int, refillRate: Double) {
        precondition(capacity > 0 && refillRate > 0)
        self.capacity = Double(capacity)
        self.refillRate = refillRate
        self.tokens = Double(capacity)
        self.lastRefillTime = ContinuousClock().now
    }
    
    /// Initialize with requests per time window
    public init(capacity: Int, per window: Duration) {
        precondition(capacity > 0 && window.toSeconds > 0)
        self.capacity = Double(capacity)
        self.refillRate = Double(capacity) / window.toSeconds
        self.tokens = Double(capacity)
        self.lastRefillTime = ContinuousClock().now
    }
    
    private func refill() {
        let now = clock.now
        let elapsed = lastRefillTime.duration(to: now).toSeconds
        let newTokens = elapsed * refillRate
        tokens = min(capacity, tokens + newTokens)
        lastRefillTime = now
    }
    
    public func acquire() async throws {
        refill()
        
        while tokens < 1.0 {
            let deficit = 1.0 - tokens
            let waitTime = Duration.seconds(deficit / refillRate)
            try await clock.sleep(for: waitTime)
            try Task.checkCancellation()
            refill()
        }
        
        tokens -= 1.0
    }
    
    public func tryAcquire() async -> Bool {
        refill()
        guard tokens >= 1.0 else { return false }
        tokens -= 1.0
        return true
    }
    
    public func timeUntilAvailable() async -> Duration {
        refill()
        if tokens >= 1.0 { return .zero }
        let deficit = 1.0 - tokens
        return .seconds(deficit / refillRate)
    }
    
    public func reset() async {
        tokens = capacity
        lastRefillTime = clock.now
    }
    
    /// Current available tokens (for monitoring)
    public var availableTokens: Double {
        tokens
    }
}

// MARK: - Leaky Bucket Rate Limiter

/// Leaky Bucket Algorithm (as a meter)
/// - Water (requests) fills the bucket
/// - Bucket leaks at a constant rate
/// - Overflow means rate limit exceeded
/// - Best for: Smoothing out traffic to a constant rate
public actor LeakyBucketRateLimiter: RateLimiter {
    private let capacity: Double
    /// units leaked per second
    private let leakRate: Double
    private var waterLevel: Double = 0
    private var lastLeakTime: ContinuousClock.Instant
    private let clock = ContinuousClock()
    
    public init(capacity: Int, leakRate: Double) {
        precondition(capacity > 0 && leakRate > 0)
        self.capacity = Double(capacity)
        self.leakRate = leakRate
        self.lastLeakTime = ContinuousClock().now
    }
    
    public init(capacity: Int, per window: Duration) {
        precondition(capacity > 0 && window.toSeconds > 0)
        self.capacity = Double(capacity)
        self.leakRate = Double(capacity) / window.toSeconds
        self.lastLeakTime = ContinuousClock().now
    }
    
    private func leak() {
        let now = clock.now
        let elapsed = lastLeakTime.duration(to: now).toSeconds
        let leaked = elapsed * leakRate
        waterLevel = max(0, waterLevel - leaked)
        lastLeakTime = now
    }
    
    public func acquire() async throws {
        leak()
        
        while waterLevel >= capacity {
            let overflow = waterLevel - capacity + 1
            let waitTime = Duration.seconds(overflow / leakRate)
            try await clock.sleep(for: waitTime)
            try Task.checkCancellation()
            leak()
        }
        
        waterLevel += 1
    }
    
    public func tryAcquire() async -> Bool {
        leak()
        guard waterLevel < capacity else { return false }
        waterLevel += 1
        return true
    }
    
    public func timeUntilAvailable() async -> Duration {
        leak()
        if waterLevel < capacity { return .zero }
        let overflow = waterLevel - capacity + 1
        return .seconds(overflow / leakRate)
    }
    
    public func reset() async {
        waterLevel = 0
        lastLeakTime = clock.now
    }
}

// MARK: - Fixed Window Rate Limiter

/// Fixed Window Algorithm
/// - Divides time into fixed windows
/// - Counts requests in current window
/// - Resets count when window expires
/// - Simple but has boundary burst issue (2x at window edges)
/// - Best for: Simple rate limiting where edge cases are acceptable
public actor FixedWindowRateLimiter: RateLimiter {
    private let limit: Int
    private let windowDuration: Duration
    private var windowStart: ContinuousClock.Instant
    private var count: Int = 0
    private let clock = ContinuousClock()
    
    public init(limit: Int, window: Duration) {
        precondition(limit > 0 && window.toSeconds > 0)
        self.limit = limit
        self.windowDuration = window
        self.windowStart = ContinuousClock().now
    }
    
    private func rotateWindowIfNeeded() {
        let now = clock.now
        let elapsed = windowStart.duration(to: now)
        
        if elapsed >= windowDuration {
            let windowsPassed = Int(elapsed.toSeconds / windowDuration.toSeconds)
            windowStart = windowStart.advanced(
                by: .seconds(Double(windowsPassed) * windowDuration.toSeconds)
            )
            count = 0
        }
    }
    
    public func acquire() async throws {
        rotateWindowIfNeeded()
        
        while count >= limit {
            let elapsed = windowStart.duration(to: clock.now)
            let remaining = windowDuration - elapsed
            try await clock.sleep(for: remaining + .milliseconds(1))
            try Task.checkCancellation()
            rotateWindowIfNeeded()
        }
        
        count += 1
    }
    
    public func tryAcquire() async -> Bool {
        rotateWindowIfNeeded()
        guard count < limit else { return false }
        count += 1
        return true
    }
    
    public func timeUntilAvailable() async -> Duration {
        rotateWindowIfNeeded()
        if count < limit { return .zero }
        let elapsed = windowStart.duration(to: clock.now)
        return windowDuration - elapsed
    }
    
    public func reset() async {
        windowStart = clock.now
        count = 0
    }
}

// MARK: - Sliding Window Log Rate Limiter

/// Sliding Window Log Algorithm
/// - Stores timestamp of each request
/// - Counts requests within sliding window
/// - Most accurate but O(n) memory
/// - Best for: When accuracy is critical and request volume is manageable
public actor SlidingWindowLogRateLimiter: RateLimiter {
    private let limit: Int
    private let windowDuration: Duration
    private var timestamps: [ContinuousClock.Instant] = []
    private let clock = ContinuousClock()
    
    public init(limit: Int, window: Duration) {
        precondition(limit > 0 && window.toSeconds > 0)
        self.limit = limit
        self.windowDuration = window
        timestamps.reserveCapacity(limit + 1)
    }
    
    private func pruneExpired() {
        let cutoff = clock.now.advanced(by: .zero - windowDuration)
        timestamps.removeAll { $0 < cutoff }
    }
    
    public func acquire() async throws {
        pruneExpired()
        
        while timestamps.count >= limit {
            guard let oldest = timestamps.first else { break }
            let age = oldest.duration(to: clock.now)
            let waitTime = windowDuration - age + .milliseconds(1)
            
            if waitTime > .zero {
                try await clock.sleep(for: waitTime)
                try Task.checkCancellation()
            }
            pruneExpired()
        }
        
        timestamps.append(clock.now)
    }
    
    public func tryAcquire() async -> Bool {
        pruneExpired()
        guard timestamps.count < limit else { return false }
        timestamps.append(clock.now)
        return true
    }
    
    public func timeUntilAvailable() async -> Duration {
        pruneExpired()
        if timestamps.count < limit { return .zero }
        guard let oldest = timestamps.first else { return .zero }
        let age = oldest.duration(to: clock.now)
        return windowDuration - age
    }
    
    public func reset() async {
        timestamps.removeAll(keepingCapacity: true)
    }
}

// MARK: - Sliding Window Counter Rate Limiter

/// Sliding Window Counter Algorithm
/// - Hybrid of fixed window with weighted previous window
/// - Approximates sliding window with O(1) memory
/// - Good balance of accuracy and efficiency
/// - Best for: Most production use cases
public actor SlidingWindowCounterRateLimiter: RateLimiter {
    private let limit: Int
    private let windowDuration: Duration
    private var currentWindowStart: ContinuousClock.Instant
    private var currentCount: Int = 0
    private var previousCount: Int = 0
    private let clock = ContinuousClock()
    
    public init(limit: Int, window: Duration) {
        precondition(limit > 0 && window.toSeconds > 0)
        self.limit = limit
        self.windowDuration = window
        self.currentWindowStart = ContinuousClock().now
    }
    
    private func rotateWindows() {
        let now = clock.now
        let elapsed = currentWindowStart.duration(to: now)
        
        if elapsed >= windowDuration {
            let windowsPassed = Int(elapsed.toSeconds / windowDuration.toSeconds)
            
            if windowsPassed == 1 {
                previousCount = currentCount
            } else {
                previousCount = 0
            }
            currentCount = 0
            currentWindowStart = currentWindowStart.advanced(
                by: .seconds(Double(windowsPassed) * windowDuration.toSeconds)
            )
        }
    }
    
    private func weightedCount() -> Double {
        let elapsed = currentWindowStart.duration(to: clock.now)
        let progress = elapsed.toSeconds / windowDuration.toSeconds
        let previousWeight = max(0, 1.0 - progress)
        return Double(currentCount) + Double(previousCount) * previousWeight
    }
    
    public func acquire() async throws {
        rotateWindows()
        
        while weightedCount() >= Double(limit) {
            let elapsed = currentWindowStart.duration(to: clock.now)
            let remaining = windowDuration - elapsed
            let sleepTime = min(remaining, .milliseconds(100))
            try await clock.sleep(for: sleepTime)
            try Task.checkCancellation()
            rotateWindows()
        }
        
        currentCount += 1
    }
    
    public func tryAcquire() async -> Bool {
        rotateWindows()
        guard weightedCount() < Double(limit) else { return false }
        currentCount += 1
        return true
    }
    
    public func timeUntilAvailable() async -> Duration {
        rotateWindows()
        if weightedCount() < Double(limit) { return .zero }
        let elapsed = currentWindowStart.duration(to: clock.now)
        return windowDuration - elapsed
    }
    
    public func reset() async {
        currentWindowStart = clock.now
        currentCount = 0
        previousCount = 0
    }
}

// MARK: - Concurrency Limiter

/// Limits concurrent operations (semaphore-style)
/// - Controls number of simultaneous in-flight operations
/// - Best for: Connection pools, parallel task limiting
public actor ConcurrencyLimiter: RateLimiter {
    private let maxConcurrent: Int
    private var current: Int = 0
    private var waiters: [CheckedContinuation<Void, Error>] = []
    
    public init(maxConcurrent: Int) {
        precondition(maxConcurrent > 0)
        self.maxConcurrent = maxConcurrent
    }
    
    public func acquire() async throws {
        try Task.checkCancellation()
        
        if current < maxConcurrent {
            current += 1
            return
        }
        
        try await withCheckedThrowingContinuation { continuation in
            waiters.append(continuation)
        }
        current += 1
    }
    
    public func release() {
        current = max(0, current - 1)
        
        if let next = waiters.first {
            waiters.removeFirst()
            next.resume()
        }
    }
    
    public func tryAcquire() async -> Bool {
        guard current < maxConcurrent else { return false }
        current += 1
        return true
    }
    
    public func timeUntilAvailable() async -> Duration {
        current < maxConcurrent ? .zero : .seconds(Double.infinity)
    }
    
    public func reset() async {
        let pending = waiters
        waiters.removeAll()
        current = 0
        for waiter in pending {
            waiter.resume(throwing: CancellationError())
        }
    }
    
    /// Execute operation with automatic acquire/release
    public func withPermit<T: Sendable>(
        operation: @Sendable () async throws -> T
    ) async throws -> T {
        try await acquire()
        do {
            let result = try await operation()
            release()
            return result
        } catch {
            release()
            throw error
        }
    }
}

// MARK: - Adaptive Rate Limiter

/// Adaptive Rate Limiter that adjusts based on success/failure
/// - Reduces rate on failures, increases on successes
/// - Best for: External APIs with unknown or varying limits
public actor AdaptiveRateLimiter: RateLimiter {
    private var currentRate: Double
    private let minRate: Double
    private let maxRate: Double
    private let increaseRatio: Double
    private let decreaseRatio: Double
    
    private var tokens: Double
    private var lastRefill: ContinuousClock.Instant
    private let clock = ContinuousClock()
    
    public init(
        initialRate: Double,
        minRate: Double,
        maxRate: Double,
        increaseRatio: Double = 1.1,
        decreaseRatio: Double = 0.5
    ) {
        precondition(minRate > 0 && minRate <= initialRate && initialRate <= maxRate)
        self.currentRate = initialRate
        self.minRate = minRate
        self.maxRate = maxRate
        self.increaseRatio = increaseRatio
        self.decreaseRatio = decreaseRatio
        self.tokens = initialRate
        self.lastRefill = ContinuousClock().now
    }
    
    private func refill() {
        let now = clock.now
        let elapsed = lastRefill.duration(to: now).toSeconds
        tokens = min(currentRate, tokens + elapsed * currentRate)
        lastRefill = now
    }
    
    public func acquire() async throws {
        refill()
        
        while tokens < 1.0 {
            let deficit = 1.0 - tokens
            let waitTime = Duration.seconds(deficit / currentRate)
            try await clock.sleep(for: waitTime)
            try Task.checkCancellation()
            refill()
        }
        
        tokens -= 1.0
    }
    
    public func tryAcquire() async -> Bool {
        refill()
        guard tokens >= 1.0 else { return false }
        tokens -= 1.0
        return true
    }
    
    public func timeUntilAvailable() async -> Duration {
        refill()
        if tokens >= 1.0 { return .zero }
        return .seconds((1.0 - tokens) / currentRate)
    }
    
    /// Call on successful request to potentially increase rate
    public func recordSuccess() {
        currentRate = min(maxRate, currentRate * increaseRatio)
    }
    
    /// Call on rate-limited response to decrease rate
    public func recordRateLimited() {
        currentRate = max(minRate, currentRate * decreaseRatio)
        tokens = min(tokens, currentRate / 2)
    }
    
    public func reset() async {
        tokens = currentRate
        lastRefill = clock.now
    }
    
    public var currentRatePerSecond: Double { currentRate }
}

// MARK: - Composite Rate Limiter

/// Combines multiple rate limiters using parameter packs
/// All limiters must allow the request for it to proceed
/// Uses pack iteration with `for-in repeat`
public actor CompositeRateLimiter<each L: RateLimiter>: RateLimiter {
    private let limiters: (repeat each L)
    
    public init(_ limiters: repeat each L) {
        self.limiters = (repeat each limiters)
    }
    
    public func acquire() async throws {
        for limiter in repeat each self.limiters {
            try await limiter.acquire()
        }
    }
    
    public func tryAcquire() async -> Bool {
        for limiter in repeat each self.limiters {
            let acquired = await limiter.tryAcquire()
            if !acquired {
                return false
            }
        }
        return true
    }
    
    public func timeUntilAvailable() async -> Duration {
        var maxWait = Duration.zero
        for limiter in repeat each self.limiters {
            let wait = await limiter.timeUntilAvailable()
            if wait > maxWait {
                maxWait = wait
            }
        }
        return maxWait
    }
    
    public func reset() async {
        for limiter in repeat each self.limiters {
            await limiter.reset()
        }
    }
}

// MARK: - Keyed Rate Limiter

/// Per-key rate limiting (e.g., per-user, per-IP)
public actor KeyedRateLimiter<Key: Hashable & Sendable> {
    public typealias LimiterFactory = @Sendable () -> any RateLimiter
    
    private var limiters: [Key: any RateLimiter] = [:]
    private let factory: LimiterFactory
    private let maxKeys: Int?
    
    public init(
        maxKeys: Int? = nil,
        factory: @escaping LimiterFactory
    ) {
        self.maxKeys = maxKeys
        self.factory = factory
    }
    
    private func getLimiter(for key: Key) -> any RateLimiter {
        if let existing = limiters[key] {
            return existing
        }
        
        // Evict oldest if at capacity (simple FIFO - in production use LRU)
        if let maxKeys = maxKeys, limiters.count >= maxKeys {
            if let firstKey = limiters.keys.first {
                limiters.removeValue(forKey: firstKey)
            }
        }
        
        let limiter = factory()
        limiters[key] = limiter
        return limiter
    }
    
    public func acquire(for key: Key) async throws {
        let limiter = getLimiter(for: key)
        try await limiter.acquire()
    }
    
    public func tryAcquire(for key: Key) async -> Bool {
        let limiter = getLimiter(for: key)
        return await limiter.tryAcquire()
    }
    
    public func reset(for key: Key) async {
        if let limiter = limiters[key] {
            await limiter.reset()
        }
    }
    
    public func resetAll() async {
        for limiter in limiters.values {
            await limiter.reset()
        }
        limiters.removeAll()
    }
    
    public var activeKeyCount: Int {
        limiters.count
    }
}
