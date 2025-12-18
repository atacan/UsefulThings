//
// https://github.com/atacan
// 16.08.25
	


import Foundation

// MARK: - Single-Single Wrapper (prefix and suffix are single elements)
public struct AsyncSequenceWrapperSingleSingle<Base: AsyncSequence>: AsyncSequence {
    public typealias Element = Base.Element

    @usableFromInline let base: Base
    @usableFromInline let prefix: Element
    @usableFromInline let suffix: Element
    
    @inlinable
    public init(_ base: Base, prefix: Element, suffix: Element) {
        self.base = base
        self.prefix = prefix
        self.suffix = suffix
    }
    
    @inlinable
    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(base: base, prefix: prefix, suffix: suffix)
    }
    
    public struct AsyncIterator: AsyncIteratorProtocol {
        @usableFromInline var baseIterator: Base.AsyncIterator
        @usableFromInline var prefixEmitted: Bool = false
        @usableFromInline var baseExhausted: Bool = false
        @usableFromInline var suffixEmitted: Bool = false
        @usableFromInline let prefix: Element
        @usableFromInline let suffix: Element
        
        @inlinable
        init(base: Base, prefix: Element, suffix: Element) {
            self.baseIterator = base.makeAsyncIterator()
            self.prefix = prefix
            self.suffix = suffix
        }
        
        @inlinable
        public mutating func next() async throws -> Element? {
            if !prefixEmitted {
                prefixEmitted = true
                return prefix
            }
            
            if !baseExhausted {
                if let element = try await baseIterator.next() {
                    return element
                }
                baseExhausted = true
            }
            
            if !suffixEmitted {
                suffixEmitted = true
                return suffix
            }
            
            return nil
        }
    }
}

// MARK: - Sequence-Sequence Wrapper (both prefix and suffix are sequences)
public struct AsyncSequenceWrapperSeqSeq<Base: AsyncSequence, Prefix: AsyncSequence, Suffix: AsyncSequence>: AsyncSequence
where Base.Element == Prefix.Element, Base.Element == Suffix.Element {
    public typealias Element = Base.Element

    @usableFromInline let base: Base
    @usableFromInline let prefix: Prefix
    @usableFromInline let suffix: Suffix
    
    @inlinable
    init(_ base: Base, prefix: Prefix, suffix: Suffix) {
        self.base = base
        self.prefix = prefix
        self.suffix = suffix
    }
    
    @inlinable
    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(
            prefixIterator: prefix.makeAsyncIterator(),
            baseIterator: base.makeAsyncIterator(),
            suffixIterator: suffix.makeAsyncIterator()
        )
    }
    
    public struct AsyncIterator: AsyncIteratorProtocol {
        @usableFromInline var prefixIterator: Prefix.AsyncIterator
        @usableFromInline var baseIterator: Base.AsyncIterator
        @usableFromInline var suffixIterator: Suffix.AsyncIterator
        @usableFromInline var prefixExhausted: Bool = false
        @usableFromInline var baseExhausted: Bool = false
        
        @inlinable
        init(prefixIterator: Prefix.AsyncIterator, baseIterator: Base.AsyncIterator, suffixIterator: Suffix.AsyncIterator) {
            self.prefixIterator = prefixIterator
            self.baseIterator = baseIterator
            self.suffixIterator = suffixIterator
        }
        
        @inlinable
        public mutating func next() async throws -> Element? {
            if !prefixExhausted {
                if let element = try await prefixIterator.next() {
                    return element
                }
                prefixExhausted = true
            }
            
            if !baseExhausted {
                if let element = try await baseIterator.next() {
                    return element
                }
                baseExhausted = true
            }
            
            return try await suffixIterator.next()
        }
    }
}

// MARK: - Single-Sequence Wrapper (prefix is single, suffix is sequence)
public struct AsyncSequenceWrapperSingleSeq<Base: AsyncSequence, Suffix: AsyncSequence>: AsyncSequence
where Base.Element == Suffix.Element {
    public typealias Element = Base.Element

    @usableFromInline let base: Base
    @usableFromInline let prefix: Element
    @usableFromInline let suffix: Suffix
    
    @inlinable
    init(_ base: Base, prefix: Element, suffix: Suffix) {
        self.base = base
        self.prefix = prefix
        self.suffix = suffix
    }
    
    @inlinable
    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(
            prefix: prefix,
            baseIterator: base.makeAsyncIterator(),
            suffixIterator: suffix.makeAsyncIterator()
        )
    }
    
    public struct AsyncIterator: AsyncIteratorProtocol {
        @usableFromInline let prefix: Element
        @usableFromInline var baseIterator: Base.AsyncIterator
        @usableFromInline var suffixIterator: Suffix.AsyncIterator
        @usableFromInline var prefixEmitted: Bool = false
        @usableFromInline var baseExhausted: Bool = false
        
        @inlinable
        init(prefix: Element, baseIterator: Base.AsyncIterator, suffixIterator: Suffix.AsyncIterator) {
            self.prefix = prefix
            self.baseIterator = baseIterator
            self.suffixIterator = suffixIterator
        }
        
        @inlinable
        public mutating func next() async throws -> Element? {
            if !prefixEmitted {
                prefixEmitted = true
                return prefix
            }
            
            if !baseExhausted {
                if let element = try await baseIterator.next() {
                    return element
                }
                baseExhausted = true
            }
            
            return try await suffixIterator.next()
        }
    }
}

// MARK: - Sequence-Single Wrapper (prefix is sequence, suffix is single)
public struct AsyncSequenceWrapperSeqSingle<Base: AsyncSequence, Prefix: AsyncSequence>: AsyncSequence
where Base.Element == Prefix.Element {
    public typealias Element = Base.Element

    @usableFromInline let base: Base
    @usableFromInline let prefix: Prefix
    @usableFromInline let suffix: Element
    
    @inlinable
    init(_ base: Base, prefix: Prefix, suffix: Element) {
        self.base = base
        self.prefix = prefix
        self.suffix = suffix
    }
    
    @inlinable
    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(
            prefixIterator: prefix.makeAsyncIterator(),
            baseIterator: base.makeAsyncIterator(),
            suffix: suffix
        )
    }
    
    public struct AsyncIterator: AsyncIteratorProtocol {
        @usableFromInline var prefixIterator: Prefix.AsyncIterator
        @usableFromInline var baseIterator: Base.AsyncIterator
        @usableFromInline let suffix: Element
        @usableFromInline var prefixExhausted: Bool = false
        @usableFromInline var baseExhausted: Bool = false
        @usableFromInline var suffixEmitted: Bool = false
        
        @inlinable
        init(prefixIterator: Prefix.AsyncIterator, baseIterator: Base.AsyncIterator, suffix: Element) {
            self.prefixIterator = prefixIterator
            self.baseIterator = baseIterator
            self.suffix = suffix
        }
        
        @inlinable
        public mutating func next() async throws -> Element? {
            if !prefixExhausted {
                if let element = try await prefixIterator.next() {
                    return element
                }
                prefixExhausted = true
            }
            
            if !baseExhausted {
                if let element = try await baseIterator.next() {
                    return element
                }
                baseExhausted = true
            }
            
            if !suffixEmitted {
                suffixEmitted = true
                return suffix
            }
            
            return nil
        }
    }
}

// MARK: - Single Prefix Only Wrapper
public struct AsyncSequenceWrapperSinglePrefix<Base: AsyncSequence>: AsyncSequence {
    public typealias Element = Base.Element

    @usableFromInline let base: Base
    @usableFromInline let prefix: Element
    
    @inlinable
    init(_ base: Base, prefix: Element) {
        self.base = base
        self.prefix = prefix
    }
    
    @inlinable
    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(prefix: prefix, baseIterator: base.makeAsyncIterator())
    }
    
    public struct AsyncIterator: AsyncIteratorProtocol {
        @usableFromInline let prefix: Element
        @usableFromInline var baseIterator: Base.AsyncIterator
        @usableFromInline var prefixEmitted: Bool = false
        
        @inlinable
        init(prefix: Element, baseIterator: Base.AsyncIterator) {
            self.prefix = prefix
            self.baseIterator = baseIterator
        }
        
        @inlinable
        public mutating func next() async throws -> Element? {
            if !prefixEmitted {
                prefixEmitted = true
                return prefix
            }
            return try await baseIterator.next()
        }
    }
}

// MARK: - Single Suffix Only Wrapper
public struct AsyncSequenceWrapperSingleSuffix<Base: AsyncSequence>: AsyncSequence {
    public typealias Element = Base.Element

    @usableFromInline let base: Base
    @usableFromInline let suffix: Element
    
    @inlinable
    init(_ base: Base, suffix: Element) {
        self.base = base
        self.suffix = suffix
    }
    
    @inlinable
    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(baseIterator: base.makeAsyncIterator(), suffix: suffix)
    }
    
    public struct AsyncIterator: AsyncIteratorProtocol {
        @usableFromInline var baseIterator: Base.AsyncIterator
        @usableFromInline let suffix: Element
        @usableFromInline var baseExhausted: Bool = false
        @usableFromInline var suffixEmitted: Bool = false
        
        @inlinable
        init(baseIterator: Base.AsyncIterator, suffix: Element) {
            self.baseIterator = baseIterator
            self.suffix = suffix
        }
        
        @inlinable
        public mutating func next() async throws -> Element? {
            if !baseExhausted {
                if let element = try await baseIterator.next() {
                    return element
                }
                baseExhausted = true
            }
            
            if !suffixEmitted {
                suffixEmitted = true
                return suffix
            }
            
            return nil
        }
    }
}

// MARK: - Sequence Prefix Only Wrapper
public struct AsyncSequenceWrapperSeqPrefix<Base: AsyncSequence, Prefix: AsyncSequence>: AsyncSequence
where Base.Element == Prefix.Element {
    public typealias Element = Base.Element

    @usableFromInline let base: Base
    @usableFromInline let prefix: Prefix
    
    @inlinable
    init(_ base: Base, prefix: Prefix) {
        self.base = base
        self.prefix = prefix
    }
    
    @inlinable
    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(
            prefixIterator: prefix.makeAsyncIterator(),
            baseIterator: base.makeAsyncIterator()
        )
    }
    
    public struct AsyncIterator: AsyncIteratorProtocol {
        @usableFromInline var prefixIterator: Prefix.AsyncIterator
        @usableFromInline var baseIterator: Base.AsyncIterator
        @usableFromInline var prefixExhausted: Bool = false
        
        @inlinable
        init(prefixIterator: Prefix.AsyncIterator, baseIterator: Base.AsyncIterator) {
            self.prefixIterator = prefixIterator
            self.baseIterator = baseIterator
        }
        
        @inlinable
        public mutating func next() async throws -> Element? {
            if !prefixExhausted {
                if let element = try await prefixIterator.next() {
                    return element
                }
                prefixExhausted = true
            }
            
            return try await baseIterator.next()
        }
    }
}

// MARK: - Sequence Suffix Only Wrapper
public struct AsyncSequenceWrapperSeqSuffix<Base: AsyncSequence, Suffix: AsyncSequence>: AsyncSequence
where Base.Element == Suffix.Element {
    public typealias Element = Base.Element

    @usableFromInline let base: Base
    @usableFromInline let suffix: Suffix
    
    @inlinable
    init(_ base: Base, suffix: Suffix) {
        self.base = base
        self.suffix = suffix
    }
    
    @inlinable
    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(
            baseIterator: base.makeAsyncIterator(),
            suffixIterator: suffix.makeAsyncIterator()
        )
    }
    
    public struct AsyncIterator: AsyncIteratorProtocol {
        @usableFromInline var baseIterator: Base.AsyncIterator
        @usableFromInline var suffixIterator: Suffix.AsyncIterator
        @usableFromInline var baseExhausted: Bool = false
        
        @inlinable
        init(baseIterator: Base.AsyncIterator, suffixIterator: Suffix.AsyncIterator) {
            self.baseIterator = baseIterator
            self.suffixIterator = suffixIterator
        }
        
        @inlinable
        public mutating func next() async throws -> Element? {
            if !baseExhausted {
                if let element = try await baseIterator.next() {
                    return element
                }
                baseExhausted = true
            }
            
            return try await suffixIterator.next()
        }
    }
}

// MARK: - Convenience Extensions
extension AsyncSequence {
    // Single element prefix and suffix
    @inlinable
    func wrapped(prefix: Element, suffix: Element) -> AsyncSequenceWrapperSingleSingle<Self> {
        AsyncSequenceWrapperSingleSingle(self, prefix: prefix, suffix: suffix)
    }
    
    // Single prefix only
    @inlinable
    func wrapped(prefix: Element) -> AsyncSequenceWrapperSinglePrefix<Self> {
        AsyncSequenceWrapperSinglePrefix(self, prefix: prefix)
    }
    
    // Single suffix only
    @inlinable
    func wrapped(suffix: Element) -> AsyncSequenceWrapperSingleSuffix<Self> {
        AsyncSequenceWrapperSingleSuffix(self, suffix: suffix)
    }
    
    // Sequence prefix and suffix
    @inlinable
    func wrapped<P: AsyncSequence, S: AsyncSequence>(
        prefix: P,
        suffix: S
    ) -> AsyncSequenceWrapperSeqSeq<Self, P, S> where P.Element == Element, S.Element == Element {
        AsyncSequenceWrapperSeqSeq(self, prefix: prefix, suffix: suffix)
    }
    
    // Sequence prefix only
    @inlinable
    func wrapped<P: AsyncSequence>(
        prefix: P
    ) -> AsyncSequenceWrapperSeqPrefix<Self, P> where P.Element == Element {
        AsyncSequenceWrapperSeqPrefix(self, prefix: prefix)
    }
    
    // Sequence suffix only
    @inlinable
    func wrapped<S: AsyncSequence>(
        suffix: S
    ) -> AsyncSequenceWrapperSeqSuffix<Self, S> where S.Element == Element {
        AsyncSequenceWrapperSeqSuffix(self, suffix: suffix)
    }
    
    // Mixed: single prefix, sequence suffix
    @inlinable
    func wrapped<S: AsyncSequence>(
        prefix: Element,
        suffix: S
    ) -> AsyncSequenceWrapperSingleSeq<Self, S> where S.Element == Element {
        AsyncSequenceWrapperSingleSeq(self, prefix: prefix, suffix: suffix)
    }
    
    // Mixed: sequence prefix, single suffix
    @inlinable
    func wrapped<P: AsyncSequence>(
        prefix: P,
        suffix: Element
    ) -> AsyncSequenceWrapperSeqSingle<Self, P> where P.Element == Element {
        AsyncSequenceWrapperSeqSingle(self, prefix: prefix, suffix: suffix)
    }
}

// MARK: - Performance Test
func performanceTest() async throws {
    // This should have EXACTLY the same performance as:
    // 1. Emit prefix
    // 2. Loop through base
    // 3. Emit suffix
    
    let base = AsyncStream<Int> { continuation in
        for i in 1...1_000_000 {
            continuation.yield(i)
        }
        continuation.finish()
    }
    
    let wrapped = base.wrapped(prefix: 0, suffix: 1_000_001)
    
    var sum = 0
    for try await value in wrapped {
        sum += value
    }
    
    print("Sum: \(sum)")
    
    // The above should compile to essentially:
    // sum += 0  // prefix
    // for await value in base { sum += value }  // base
    // sum += 1_000_001  // suffix
    
    // No enum checks, no protocol dispatch, no heap allocations
    // Just direct, inlined code
}

// MARK: - Example usage
func exampleUsage() async throws {
    // Example 1: Single element prefix and suffix
    let stream1 = AsyncStream<Int> { continuation in
        for i in 1...3 {
            continuation.yield(i)
        }
        continuation.finish()
    }
    
    let wrapped1 = stream1.wrapped(prefix: 0, suffix: 4)
    
    print("Example 1: Single element prefix and suffix")
    for try await value in wrapped1 {
        print(value) // Will print: 0, 1, 2, 3, 4
    }
    
    // Example 2: AsyncSequence as prefix and suffix
    let prefixStream = AsyncStream<Int> { continuation in
        continuation.yield(-2)
        continuation.yield(-1)
        continuation.finish()
    }
    
    let suffixStream = AsyncStream<Int> { continuation in
        continuation.yield(10)
        continuation.yield(11)
        continuation.finish()
    }
    
    let stream2 = AsyncStream<Int> { continuation in
        for i in 1...3 {
            continuation.yield(i)
        }
        continuation.finish()
    }
    
    let wrapped2 = stream2.wrapped(prefix: prefixStream, suffix: suffixStream)
    
    print("\nExample 2: AsyncSequence prefix and suffix")
    for try await value in wrapped2 {
        print(value) // Will print: -2, -1, 1, 2, 3, 10, 11
    }
}
