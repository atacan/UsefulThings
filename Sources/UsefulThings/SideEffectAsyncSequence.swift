import Foundation

/// A wrapper around an AsyncSequence that performs a side effect on each element
/// while passing the original sequence through unchanged.
/// The side effect can be performed concurrently by adding the effects to a queue. Otherwise, it is synchronous and will block the sequence consumption.
/// ```swift
/// let queue = AsyncQueue(attributes: []) // not concurrent
/// let tasks = LockIsolated([Task<Void, Error>]())
/// let teedIncomingBody = SideEffectAsyncSequence(base: request.body) { element in
///     let task = queue.addOperation {
///         try await writer.write(Data(buffer: element))
///     }
///     tasks.withValue({$0.append(task)})
/// }
///
/// /* USE THE SEQUENCE */
/// 
/// // Then when the consumption is done, wait for all the tasks to complete to ensure all the elements have been side-effected
/// for task in tasks.value {
///     try await task.value
/// }
/// ```
public struct SideEffectAsyncSequence<Base: AsyncSequence & Sendable>: AsyncSequence, Sendable {
    public typealias Element = Base.Element
    
    private let base: Base
    private let process: @Sendable (Element) -> Void

    /// Initialize with a base sequence and a closure to process each element
    /// - Parameters:
    ///   - base: The original AsyncSequence to wrap
    ///   - process: A closure that performs a side effect on each element
    public init(
        base: Base,
        process: @Sendable @escaping (Element) -> Void
    ) {
        self.base = base
        self.process = process
    }
    
    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(
            base: base.makeAsyncIterator(),
            process: process
        )
    }
    
    public struct AsyncIterator: AsyncIteratorProtocol {
        var baseIterator: Base.AsyncIterator
        let process: (Element) async throws -> Void
        
        init(
            base: Base.AsyncIterator,
            process: @escaping (Element) -> Void
        ) {
            self.baseIterator = base
            self.process = process
        }
        
        public mutating func next() async throws -> Element? {
            guard let element = try await baseIterator.next() else {
                return nil
            }
            try await process(element)

            return element
        }        
    }
}
