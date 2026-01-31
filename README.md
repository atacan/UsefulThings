# UsefulThings

A zero-dependency Swift utility library for async/await concurrency, rate limiting, retry logic, circuit breakers, and more. Built with Swift 6.1 and structured concurrency.

```swift
.package(url: "https://github.com/atacan/UsefulThings.git", from: "1.0.0")
```

## Rate Limiting

Eight actor-based, thread-safe rate limiter implementations behind a shared `RateLimiter` protocol. All are `Sendable` and safe for concurrent use.

### Token Bucket

Classic token bucket algorithm. Tokens accumulate over time and allow controlled bursts.

```swift
let limiter = TokenBucketRateLimiter(capacity: 10, per: .seconds(1))
try await limiter.acquire()
```

### Leaky Bucket

Requests drain at a fixed rate, smoothing out traffic spikes.

```swift
let limiter = LeakyBucketRateLimiter(capacity: 10, per: .seconds(1))
try await limiter.acquire()
```

### Fixed Window

Counts requests within fixed time intervals. Simple and low-overhead.

```swift
let limiter = FixedWindowRateLimiter(limit: 100, window: .seconds(60))
```

### Sliding Window Log

Tracks individual request timestamps for precise limiting. Most accurate, O(n) memory.

```swift
let limiter = SlidingWindowLogRateLimiter(limit: 100, window: .seconds(60))
```

### Sliding Window Counter

Hybrid approach that approximates a sliding window with O(1) memory.

```swift
let limiter = SlidingWindowCounterRateLimiter(limit: 100, window: .seconds(60))
```

### Concurrency Limiter

Semaphore-style limiter that caps the number of concurrent operations.

```swift
let limiter = ConcurrencyLimiter(maxConcurrent: 5)
try await limiter.withPermit {
    // at most 5 concurrent executions
}
```

### Adaptive Rate Limiter

Automatically adjusts its rate based on success/failure feedback from downstream services.

```swift
let limiter = AdaptiveRateLimiter(initialRate: 10.0, minRate: 1.0, maxRate: 100.0)
// call limiter.recordSuccess() or limiter.recordRateLimited() to adjust
```

### Composite Rate Limiter

Combines multiple limiters using Swift parameter packs. A request must pass all of them.

```swift
let composite = CompositeRateLimiter(tokenBucket, fixedWindow)
try await composite.acquire()
```

### Keyed Rate Limiter

Per-key limiting (e.g. per-user, per-IP). Creates limiters on demand.

```swift
let keyed = KeyedRateLimiter { TokenBucketRateLimiter(capacity: 10, per: .seconds(1)) }
try await keyed.acquire(forKey: userId)
```

## Retry with Exponential Backoff

Retry operations with configurable exponential backoff, jitter, typed throws, and cancellation support.

```swift
let result = try await withRetry(configuration: .default) {
    try await fetchFromAPI()
}
```

### Retry Configuration Presets

| Preset | Attempts | Initial Delay | Max Delay | Backoff | Jitter |
|---|---|---|---|---|---|
| `.default` | 3 | 1s | 30s | 2.0x | 0.25 |
| `.aggressive` | 5 | 0.5s | 60s | 2.0x | 0.25 |
| `.conservative` | 10 | 2s | 120s | 3.0x | 0.5 |

### Retry Predicates

Control which errors trigger retries with composable predicates.

```swift
try await withRetry(
    predicate: .on(NetworkError.self).and(.except(AuthError.self))
) {
    try await fetchFromAPI()
}
```

### Retry with Timeout

Abort the entire retry sequence if a deadline is exceeded.

```swift
try await withRetry(configuration: .aggressive, timeout: .seconds(30)) {
    try await fetchFromAPI()
}
```

### Retry with Rate Limiter

Combine retries with rate limiting to avoid hammering a struggling service.

```swift
let limiter = TokenBucketRateLimiter(capacity: 5, per: .seconds(1))
let result = try await withRetry(rateLimiter: limiter) {
    try await fetchFromAPI()
}
```

## Circuit Breaker

Prevent cascading failures by stopping calls to a failing dependency. Transitions through closed, open, and half-open states.

```swift
let breaker = CircuitBreaker(failureThreshold: 5, successThreshold: 2, timeout: .seconds(30))
let result = try await breaker.execute {
    try await callExternalService()
}
```

## Combined Resilience

Apply rate limiting, circuit breaking, and retries in a single call.

```swift
try await withResilience(
    rateLimiter: limiter,
    circuitBreaker: breaker,
    retryConfiguration: .default
) {
    try await callExternalService()
}
```

## Polling

Poll an operation until a condition is met, with exponential backoff and jitter.

```swift
let result = try await pollUntil(
    configuration: PollingConfiguration(maxRetries: 10, baseDelay: .seconds(1), maxDelay: .seconds(32))
) {
    try await checkJobStatus()
} until: { status in
    status == .completed
}
```

## AsyncSequence Utilities

### Prepend and Append to AsyncSequence

Wrap any `AsyncSequence` with prefix and/or suffix elements or sequences. Zero-cost abstractions using `@inlinable`.

```swift
let wrapped = stream.wrapped(prefix: headerElement, suffix: trailerElement)

for await element in wrapped {
    // headerElement, then all stream elements, then trailerElement
}
```

### FileHandle as AsyncSequence

Read files asynchronously in chunks using `for await`.

```swift
let handle = FileHandle(forReadingAtPath: "/path/to/file")!
for try await chunk in handle {
    // chunk is ArraySlice<UInt8>, default 64KB
}
```

### Side Effect AsyncSequence

Tap into an `AsyncSequence` to perform side effects on each element without transforming it.

```swift
let tapped = SideEffectAsyncSequence(base: stream, process: { element in
    logger.log("Received: \(element)")
}, onFinish: {
    logger.log("Stream complete")
})
```

## Shell Command Execution (macOS)

Run shell commands and external processes from Swift.

```swift
let output = try runCommand("ls -la")
let info = try runExternalCommand(executablePath: "/usr/bin/git", arguments: ["status"])
let probe = try runFfprobe(ffprobeArguments: ["-show_format", "video.mp4"])
```

## Environment Variables

Read environment variables from the system or fall back to a `.env` file.

```swift
let apiKey = getEnvironmentVariable("API_KEY", from: envFileUrl)
```

## JSON Encoding

Pretty-print any `Encodable` value as formatted JSON.

```swift
let data = try prettyEncode(myStruct)
```

## Byte Conversions

Convert a `Double` to its raw `[UInt8]` byte representation.

```swift
let bytes = doubleToUInt8Array(3.14)
```

## Requirements

- Swift 6.1+
- macOS 14.0+ / iOS 17.0+ / watchOS 7.0+ / tvOS 14.0+ / visionOS 1.0+
- No external dependencies

## Installation

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/atacan/UsefulThings.git", branch: "main")
]
```

Then add `"UsefulThings"` to the target dependencies:

```swift
.target(
    name: "YourTarget",
    dependencies: ["UsefulThings"]
)
```

## License

See [LICENSE](LICENSE) for details.
