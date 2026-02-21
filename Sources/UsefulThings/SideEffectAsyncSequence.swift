import Foundation

/// A wrapper around an AsyncSequence that performs a side effect on each element
/// while passing the original sequence through unchanged.
/// The side effect can be performed concurrently by yielding elements into an `AsyncStream`.
/// Otherwise, it is synchronous and will block sequence consumption.
/// ```swift
/// let (stream, continuation) = AsyncStream.makeStream(of: ByteBuffer.self)
/// let sideEffectTask = Task {
///     for await element in stream {
///         try await writer.write(Data(buffer: element))
///     }
/// }
///
/// let teedIncomingBody = SideEffectAsyncSequence(
///     base: request.body,
///     process: { element in
///         continuation.yield(element)
///     },
///     onFinish: {
///         continuation.finish()
///     }
/// )
///
/// /* USE THE SEQUENCE */
/// 
/// // Wait for side effects after sequence consumption completes.
/// try await sideEffectTask.value
/// ```
public struct SideEffectAsyncSequence<Base: AsyncSequence & Sendable>: AsyncSequence, Sendable {
    public typealias Element = Base.Element
    
    private let base: Base
    private let process: @Sendable (Element) -> Void
    private let onFinish: (@Sendable () throws -> Void)?

    /// Initialize with a base sequence and a closure to process each element
    /// - Parameters:
    ///   - base: The original AsyncSequence to wrap
    ///   - process: A closure that performs a side effect on each element
    ///   - onFinish: An optional closure to run when the sequence finishes
    public init(
        base: Base,
        process: @Sendable @escaping (Element) -> Void,
        onFinish: (@Sendable () throws -> Void)? = nil
    ) {
        self.base = base
        self.process = process
        self.onFinish = onFinish
    }
    
    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(
            base: base.makeAsyncIterator(),
            process: process,
            onFinish: onFinish
        )
    }
    
    public struct AsyncIterator: AsyncIteratorProtocol {
        var baseIterator: Base.AsyncIterator
        let process: (Element) async throws -> Void
        let onFinish: (@Sendable () throws -> Void)?
        
        init(
            base: Base.AsyncIterator,
            process: @escaping (Element) -> Void,
            onFinish: (@Sendable () throws -> Void)?
        ) {
            self.baseIterator = base
            self.process = process
            self.onFinish = onFinish
        }
        
        public mutating func next() async throws -> Element? {
            guard let element = try await baseIterator.next() else {
                try onFinish?()
                return nil
            }
            try await process(element)

            return element
        }        
    }
}
