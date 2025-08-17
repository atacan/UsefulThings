import XCTest
@testable import UsefulThings

final class SideEffectAsyncSequenceTests: XCTestCase {
    
    func testElementPassthrough() async throws {
        let originalElements = [1, 2, 3, 4, 5]
        let baseSequence = AsyncStream<Int> { continuation in
            for element in originalElements {
                continuation.yield(element)
            }
            continuation.finish()
        }
        
        actor SideEffectCollector {
            private var calls: [Int] = []
            
            func addCall(_ element: Int) {
                calls.append(element)
            }
            
            func getCalls() -> [Int] {
                return calls
            }
        }
        
        let collector = SideEffectCollector()
        let sideEffectSequence = SideEffectAsyncSequence(
            base: baseSequence,
            process: { element in
                Task { await collector.addCall(element) }
            }
        )
        
        var collectedElements: [Int] = []
        for try await element in sideEffectSequence {
            collectedElements.append(element)
        }
        
        try await Task.sleep(nanoseconds: 10_000_000)
        let sideEffectCalls = await collector.getCalls()
        
        XCTAssertEqual(collectedElements, originalElements, "Elements should pass through unchanged")
        XCTAssertEqual(sideEffectCalls, originalElements, "Side effect should be called for each element")
    }
    
    func testSideEffectProcessing() async throws {
        let elements = ["a", "b", "c"]
        let baseSequence = AsyncStream<String> { continuation in
            for element in elements {
                continuation.yield(element)
            }
            continuation.finish()
        }
        
        actor ProcessingCollector {
            private var processedElements: [String] = []
            
            func addProcessed(_ element: String) {
                processedElements.append(element.uppercased())
            }
            
            func getProcessed() -> [String] {
                return processedElements
            }
        }
        
        let collector = ProcessingCollector()
        let sideEffectSequence = SideEffectAsyncSequence(
            base: baseSequence,
            process: { element in
                Task { await collector.addProcessed(element) }
            }
        )
        
        var elementCount = 0
        for try await _ in sideEffectSequence {
            elementCount += 1
        }
        
        try await Task.sleep(nanoseconds: 10_000_000)
        let processedElements = await collector.getProcessed()
        
        XCTAssertEqual(processedElements, ["A", "B", "C"])
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
        
        actor FinishCollector {
            private var finishCallCount = 0
            private var finishCallValue: Int?
            private var processedSum = 0
            
            func addToSum(_ element: Int) {
                processedSum += element
            }
            
            func recordFinish() {
                finishCallCount += 1
                finishCallValue = processedSum
            }
            
            func getFinishCount() -> Int { finishCallCount }
            func getFinishValue() -> Int? { finishCallValue }
        }
        
        let collector = FinishCollector()
        let sideEffectSequence = SideEffectAsyncSequence(
            base: baseSequence,
            process: { element in
                Task { await collector.addToSum(element) }
            },
            onFinish: {
                Task { await collector.recordFinish() }
            }
        )
        
        var totalSum = 0
        for try await element in sideEffectSequence {
            totalSum += element
        }
        
        try await Task.sleep(nanoseconds: 10_000_000)
        let finishCallCount = await collector.getFinishCount()
        let finishCallValue = await collector.getFinishValue()
        
        XCTAssertEqual(totalSum, 60, "Total sum should be correct")
        XCTAssertEqual(finishCallCount, 1, "onFinish should be called exactly once")
        XCTAssertEqual(finishCallValue, 60, "onFinish should see the final processed sum")
    }
    
    func testOnFinishNotCalledWhenNotProvided() async throws {
        let elements = [1, 2]
        let baseSequence = AsyncStream<Int> { continuation in
            for element in elements {
                continuation.yield(element)
            }
            continuation.finish()
        }
        
        actor CallCounter {
            private var sideEffectCalls = 0
            
            func increment() {
                sideEffectCalls += 1
            }
            
            func getCount() -> Int { sideEffectCalls }
        }
        
        let counter = CallCounter()
        let sideEffectSequence = SideEffectAsyncSequence(
            base: baseSequence,
            process: { _ in
                Task { await counter.increment() }
            }
        )
        
        var elementCount = 0
        for try await _ in sideEffectSequence {
            elementCount += 1
        }
        
        try await Task.sleep(nanoseconds: 10_000_000)
        let sideEffectCalls = await counter.getCount()
        
        XCTAssertEqual(elementCount, 2)
        XCTAssertEqual(sideEffectCalls, 2)
    }
    
    func testAsyncStreamContinuationQueuedProcessing() async throws {
        let inputElements = [1, 2, 3, 4, 5]
        let baseSequence = AsyncStream<Int> { continuation in
            for element in inputElements {
                continuation.yield(element)
            }
            continuation.finish()
        }
        
        let (taskStream, taskContinuation) = AsyncStream<Task<String, Never>>.makeStream()
        
        let sideEffectSequence = SideEffectAsyncSequence(
            base: baseSequence,
            process: { element in
                let task = Task<String, Never> {
                    try? await Task.sleep(nanoseconds: UInt64.random(in: 1_000_000...10_000_000))
                    return "processed-\(element)"
                }
                taskContinuation.yield(task)
            },
            onFinish: {
                taskContinuation.finish()
            }
        )
        
        var mainThreadElements: [Int] = []
        let startTime = CFAbsoluteTimeGetCurrent()
        
        for try await element in sideEffectSequence {
            mainThreadElements.append(element)
        }
        
        let mainLoopTime = CFAbsoluteTimeGetCurrent() - startTime
        
        var allTasks: [Task<String, Never>] = []
        for await task in taskStream {
            allTasks.append(task)
        }
        
        var processedResults: [String] = []
        for task in allTasks {
            let result = await task.value
            processedResults.append(result)
        }
        
        let totalTime = CFAbsoluteTimeGetCurrent() - startTime
        
        XCTAssertEqual(mainThreadElements, inputElements, "Main thread should get all elements in order")
        XCTAssertEqual(processedResults.count, 5, "All background tasks should complete")
        XCTAssertTrue(mainLoopTime < 0.05, "Main loop should complete quickly without waiting for background tasks")
        XCTAssertTrue(totalTime > mainLoopTime, "Total time should include background processing")
        
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
        
        actor StateCollector {
            private var finishCalled = false
            private var processCalled = false
            
            func markFinishCalled() { finishCalled = true }
            func markProcessCalled() { processCalled = true }
            
            func getFinishCalled() -> Bool { finishCalled }
            func getProcessCalled() -> Bool { processCalled }
        }
        
        let collector = StateCollector()
        let sideEffectSequence = SideEffectAsyncSequence(
            base: baseSequence,
            process: { _ in
                Task { await collector.markProcessCalled() }
            },
            onFinish: {
                Task { await collector.markFinishCalled() }
            }
        )
        
        var elementCount = 0
        for try await _ in sideEffectSequence {
            elementCount += 1
        }
        
        try await Task.sleep(nanoseconds: 10_000_000)
        let finishCalled = await collector.getFinishCalled()
        let processCalled = await collector.getProcessCalled()
        
        XCTAssertEqual(elementCount, 0, "Empty sequence should yield no elements")
        XCTAssertFalse(processCalled, "Process should not be called for empty sequence")
        XCTAssertTrue(finishCalled, "onFinish should still be called for empty sequence")
    }
}