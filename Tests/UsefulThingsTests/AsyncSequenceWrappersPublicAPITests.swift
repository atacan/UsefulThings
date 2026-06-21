import Testing
import UsefulThings

@Suite("AsyncSequence Wrappers Public API Tests")
struct AsyncSequenceWrappersPublicAPITests {
    @Test("Convenience overloads are available through public import")
    func convenienceOverloadsArePublic() {
        let base = AsyncStream<Int> { continuation in
            continuation.yield(2)
            continuation.finish()
        }
        let prefix = AsyncStream<Int> { continuation in
            continuation.yield(1)
            continuation.finish()
        }
        let suffix = AsyncStream<Int> { continuation in
            continuation.yield(3)
            continuation.finish()
        }

        _ = base.wrapped(prefix: 1, suffix: 3)
        _ = base.wrapped(prefix: 1)
        _ = base.wrapped(suffix: 3)
        _ = base.wrapped(prefix: prefix, suffix: suffix)
        _ = base.wrapped(prefix: prefix)
        _ = base.wrapped(suffix: suffix)
        _ = base.wrapped(prefix: 1, suffix: suffix)
        _ = base.wrapped(prefix: prefix, suffix: 3)
    }

    @Test("Wrapper initializers are available through public import")
    func wrapperInitializersArePublic() {
        let base = AsyncStream<Int> { continuation in
            continuation.yield(2)
            continuation.finish()
        }
        let prefix = AsyncStream<Int> { continuation in
            continuation.yield(1)
            continuation.finish()
        }
        let suffix = AsyncStream<Int> { continuation in
            continuation.yield(3)
            continuation.finish()
        }

        _ = AsyncSequenceWrapperSingleSingle(base, prefix: 1, suffix: 3)
        _ = AsyncSequenceWrapperSeqSeq(base, prefix: prefix, suffix: suffix)
        _ = AsyncSequenceWrapperSingleSeq(base, prefix: 1, suffix: suffix)
        _ = AsyncSequenceWrapperSeqSingle(base, prefix: prefix, suffix: 3)
        _ = AsyncSequenceWrapperSinglePrefix(base, prefix: 1)
        _ = AsyncSequenceWrapperSingleSuffix(base, suffix: 3)
        _ = AsyncSequenceWrapperSeqPrefix(base, prefix: prefix)
        _ = AsyncSequenceWrapperSeqSuffix(base, suffix: suffix)
    }
}
