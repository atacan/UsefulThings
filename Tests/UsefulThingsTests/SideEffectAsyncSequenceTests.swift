import XCTest
@testable import UsefulThings

final class SideEffectAsyncSequenceTests: XCTestCase {

    // Simple collector class - safe because SideEffectAsyncSequence iterates serially
    // @unchecked Sendable is safe here because iteration happens one element at a time
    final class SyncCollector<T>: @unchecked Sendable {
        var items: [T] = []
        func append(_ item: T) { items.append(item) }
    }

    func testElementPassthrough() async throws {
        let originalElements = [1, 2, 3, 4, 5]
        let baseSequence = AsyncStream<Int> { continuation in
            for element in originalElements {
                continuation.yield(element)
            }
            continuation.finish()
        }

        let collector = SyncCollector<Int>()
        let sideEffectSequence = SideEffectAsyncSequence(
            base: baseSequence,
            process: { element in
                collector.append(element)
            }
        )

        var collectedElements: [Int] = []
        for try await element in sideEffectSequence {
            collectedElements.append(element)
        }

        XCTAssertEqual(collectedElements, originalElements, "Elements should pass through unchanged")
        XCTAssertEqual(collector.items, originalElements, "Side effect should be called for each element")
    }
    
    func testSideEffectProcessing() async throws {
        let elements = ["a", "b", "c"]
        let baseSequence = AsyncStream<String> { continuation in
            for element in elements {
                continuation.yield(element)
            }
            continuation.finish()
        }

        let collector = SyncCollector<String>()
        let sideEffectSequence = SideEffectAsyncSequence(
            base: baseSequence,
            process: { element in
                collector.append(element.uppercased())
            }
        )

        var elementCount = 0
        for try await _ in sideEffectSequence {
            elementCount += 1
        }

        XCTAssertEqual(collector.items, ["A", "B", "C"])
        XCTAssertEqual(elementCount, 3)
    }
    
    func testOnFinishClosure() async throws {
        let elements = [10, 20, 30]
        let baseSequence = AsyncStream<Int> { continuation in
            for element in elements {
                continuation.yield(element)
            }
            continuation.finish()
        }

        final class FinishCollector: @unchecked Sendable {
            var finishCallCount = 0
            var finishCallValue: Int?
            var processedSum = 0

            func addToSum(_ element: Int) { processedSum += element }
            func recordFinish() {
                finishCallCount += 1
                finishCallValue = processedSum
            }
        }

        let collector = FinishCollector()
        let sideEffectSequence = SideEffectAsyncSequence(
            base: baseSequence,
            process: { element in
                collector.addToSum(element)
            },
            onFinish: {
                collector.recordFinish()
            }
        )

        var totalSum = 0
        for try await element in sideEffectSequence {
            totalSum += element
        }

        XCTAssertEqual(totalSum, 60, "Total sum should be correct")
        XCTAssertEqual(collector.finishCallCount, 1, "onFinish should be called exactly once")
        XCTAssertEqual(collector.finishCallValue, 60, "onFinish should see the final processed sum")
    }
    
    func testOnFinishNotCalledWhenNotProvided() async throws {
        let elements = [1, 2]
        let baseSequence = AsyncStream<Int> { continuation in
            for element in elements {
                continuation.yield(element)
            }
            continuation.finish()
        }

        final class CallCounter: @unchecked Sendable {
            var sideEffectCalls = 0
            func increment() { sideEffectCalls += 1 }
        }

        let counter = CallCounter()
        let sideEffectSequence = SideEffectAsyncSequence(
            base: baseSequence,
            process: { _ in
                counter.increment()
            }
        )

        var elementCount = 0
        for try await _ in sideEffectSequence {
            elementCount += 1
        }

        XCTAssertEqual(elementCount, 2)
        XCTAssertEqual(counter.sideEffectCalls, 2)
    }
    
    func testAsyncStreamContinuationQueuedProcessing() async throws {
        let inputElements = [1, 2, 3, 4, 5]
        let baseSequence = AsyncStream<Int> { continuation in
            for element in inputElements {
                continuation.yield(element)
            }
            continuation.finish()
        }

        final class TaskContinuationHolder: @unchecked Sendable {
            let continuation: AsyncStream<Task<String, Never>>.Continuation
            init(_ continuation: AsyncStream<Task<String, Never>>.Continuation) {
                self.continuation = continuation
            }
        }

        let (taskStream, taskContinuation) = AsyncStream<Task<String, Never>>.makeStream()
        let holder = TaskContinuationHolder(taskContinuation)

        let sideEffectSequence = SideEffectAsyncSequence(
            base: baseSequence,
            process: { element in
                let task = Task<String, Never> {
                    try? await Task.sleep(nanoseconds: UInt64.random(in: 1_000_000...10_000_000))
                    return "processed-\(element)"
                }
                holder.continuation.yield(task)
            },
            onFinish: {
                holder.continuation.finish()
            }
        )

        var mainThreadElements: [Int] = []
        for try await element in sideEffectSequence {
            mainThreadElements.append(element)
        }

        var allTasks: [Task<String, Never>] = []
        for await task in taskStream {
            allTasks.append(task)
        }

        var processedResults: [String] = []
        for task in allTasks {
            let result = await task.value
            processedResults.append(result)
        }

        XCTAssertEqual(mainThreadElements, inputElements, "Main thread should get all elements in order")
        XCTAssertEqual(processedResults.count, 5, "All background tasks should complete")

        let expectedResults = Set(["processed-1", "processed-2", "processed-3", "processed-4", "processed-5"])
        XCTAssertEqual(Set(processedResults), expectedResults, "All elements should be processed")
    }
    
    func testErrorInOnFinish() async throws {
        let elements = [1, 2]
        let baseSequence = AsyncStream<Int> { continuation in
            for element in elements {
                continuation.yield(element)
            }
            continuation.finish()
        }
        
        struct TestError: Error, Equatable {}
        
        let sideEffectSequence = SideEffectAsyncSequence(
            base: baseSequence,
            process: { _ in },
            onFinish: {
                throw TestError()
            }
        )
        
        var collectedElements: [Int] = []
        
        do {
            for try await element in sideEffectSequence {
                collectedElements.append(element)
            }
            XCTFail("Should have thrown an error")
        } catch {
            XCTAssertTrue(error is TestError, "Should throw the TestError from onFinish")
            XCTAssertEqual(collectedElements, [1, 2], "Should have processed all elements before error")
        }
    }
    
    func testEmptySequence() async throws {
        let baseSequence = AsyncStream<Int> { continuation in
            continuation.finish()
        }

        final class StateCollector: @unchecked Sendable {
            var finishCalled = false
            var processCalled = false
        }

        let collector = StateCollector()
        let sideEffectSequence = SideEffectAsyncSequence(
            base: baseSequence,
            process: { _ in
                collector.processCalled = true
            },
            onFinish: {
                collector.finishCalled = true
            }
        )

        var elementCount = 0
        for try await _ in sideEffectSequence {
            elementCount += 1
        }

        XCTAssertEqual(elementCount, 0, "Empty sequence should yield no elements")
        XCTAssertFalse(collector.processCalled, "Process should not be called for empty sequence")
        XCTAssertTrue(collector.finishCalled, "onFinish should still be called for empty sequence")
    }
}