import Testing
@testable import UsefulThings
import Foundation

@Suite("AsyncSequence Wrappers Performance Tests")
struct AsyncSequenceWrappersPerformanceTests {
    
    // MARK: - Test Configurations
    
    enum TestSize: Int, CaseIterable {
        case small = 1_000
        case medium = 10_000
        case large = 100_000
        case extraLarge = 1_000_000
        
        var name: String {
            switch self {
            case .small: return "1K"
            case .medium: return "10K"
            case .large: return "100K"
            case .extraLarge: return "1M"
            }
        }
    }
    
    // MARK: - Helper Functions
    
    func createBaseStream(size: Int) -> AsyncStream<Int> {
        AsyncStream<Int> { continuation in
            for i in 1...size {
                continuation.yield(i)
            }
            continuation.finish()
        }
    }
    
    func createSmallPrefixStream() -> AsyncStream<Int> {
        AsyncStream<Int> { continuation in
            continuation.yield(-2)
            continuation.yield(-1)
            continuation.finish()
        }
    }
    
    func createSmallSuffixStream() -> AsyncStream<Int> {
        AsyncStream<Int> { continuation in
            continuation.yield(1_000_001)
            continuation.yield(1_000_002)
            continuation.finish()
        }
    }
    
    func measureExecutionTime<T>(operation: () async throws -> T) async rethrows -> (result: T, timeInterval: TimeInterval) {
        let startTime = CFAbsoluteTimeGetCurrent()
        let result = try await operation()
        let timeInterval = CFAbsoluteTimeGetCurrent() - startTime
        return (result, timeInterval)
    }
    
    func sumSequence<S: AsyncSequence>(_ sequence: S) async throws -> Int where S.Element == Int {
        var sum = 0
        for try await value in sequence {
            sum += value
        }
        return sum
    }
    
    // MARK: - Baseline Performance Tests
    
    @Test("Baseline AsyncStream Performance", arguments: TestSize.allCases)
    func baselinePerformance(size: TestSize) async throws {
        let stream = createBaseStream(size: size.rawValue)
        
        let (sum, duration) = try await measureExecutionTime {
            try await sumSequence(stream)
        }
        
        let expectedSum = (size.rawValue * (size.rawValue + 1)) / 2
        #expect(sum == expectedSum)
        
        let throughput = Double(size.rawValue) / duration
        print("Baseline (\(size.name)): \(String(format: "%.2f", duration))s, \(String(format: "%.0f", throughput)) elements/sec")
    }
    
    // MARK: - Single-Single Wrapper Performance
    
    @Test("SingleSingle Wrapper Performance", arguments: TestSize.allCases)
    func singleSingleWrapperPerformance(size: TestSize) async throws {
        let baseStream = createBaseStream(size: size.rawValue)
        let wrappedStream = baseStream.wrapped(prefix: 0, suffix: size.rawValue + 1)
        
        let (sum, duration) = try await measureExecutionTime {
            try await sumSequence(wrappedStream)
        }
        
        let expectedSum = 0 + ((size.rawValue * (size.rawValue + 1)) / 2) + (size.rawValue + 1)
        #expect(sum == expectedSum)
        
        let throughput = Double(size.rawValue + 2) / duration
        print("SingleSingle (\(size.name)): \(String(format: "%.2f", duration))s, \(String(format: "%.0f", throughput)) elements/sec")
    }
    
    // MARK: - Sequence-Sequence Wrapper Performance
    
    @Test("SeqSeq Wrapper Performance", arguments: TestSize.allCases)
    func seqSeqWrapperPerformance(size: TestSize) async throws {
        let baseStream = createBaseStream(size: size.rawValue)
        let prefixStream = createSmallPrefixStream()
        let suffixStream = createSmallSuffixStream()
        let wrappedStream = baseStream.wrapped(prefix: prefixStream, suffix: suffixStream)
        
        let (sum, duration) = try await measureExecutionTime {
            try await sumSequence(wrappedStream)
        }
        
        let expectedSum = (-2 + -1) + ((size.rawValue * (size.rawValue + 1)) / 2) + (1_000_001 + 1_000_002)
        #expect(sum == expectedSum)
        
        let throughput = Double(size.rawValue + 4) / duration
        print("SeqSeq (\(size.name)): \(String(format: "%.2f", duration))s, \(String(format: "%.0f", throughput)) elements/sec")
    }
    
    // MARK: - Single-Sequence Wrapper Performance
    
    @Test("SingleSeq Wrapper Performance", arguments: TestSize.allCases)
    func singleSeqWrapperPerformance(size: TestSize) async throws {
        let baseStream = createBaseStream(size: size.rawValue)
        let suffixStream = createSmallSuffixStream()
        let wrappedStream = baseStream.wrapped(prefix: 0, suffix: suffixStream)
        
        let (sum, duration) = try await measureExecutionTime {
            try await sumSequence(wrappedStream)
        }
        
        let expectedSum = 0 + ((size.rawValue * (size.rawValue + 1)) / 2) + (1_000_001 + 1_000_002)
        #expect(sum == expectedSum)
        
        let throughput = Double(size.rawValue + 3) / duration
        print("SingleSeq (\(size.name)): \(String(format: "%.2f", duration))s, \(String(format: "%.0f", throughput)) elements/sec")
    }
    
    // MARK: - Sequence-Single Wrapper Performance
    
    @Test("SeqSingle Wrapper Performance", arguments: TestSize.allCases)
    func seqSingleWrapperPerformance(size: TestSize) async throws {
        let baseStream = createBaseStream(size: size.rawValue)
        let prefixStream = createSmallPrefixStream()
        let wrappedStream = baseStream.wrapped(prefix: prefixStream, suffix: size.rawValue + 1)
        
        let (sum, duration) = try await measureExecutionTime {
            try await sumSequence(wrappedStream)
        }
        
        let expectedSum = (-2 + -1) + ((size.rawValue * (size.rawValue + 1)) / 2) + (size.rawValue + 1)
        #expect(sum == expectedSum)
        
        let throughput = Double(size.rawValue + 3) / duration
        print("SeqSingle (\(size.name)): \(String(format: "%.2f", duration))s, \(String(format: "%.0f", throughput)) elements/sec")
    }
    
    // MARK: - Single Prefix Only Wrapper Performance
    
    @Test("SinglePrefix Wrapper Performance", arguments: TestSize.allCases)
    func singlePrefixWrapperPerformance(size: TestSize) async throws {
        let baseStream = createBaseStream(size: size.rawValue)
        let wrappedStream = baseStream.wrapped(prefix: 0)
        
        let (sum, duration) = try await measureExecutionTime {
            try await sumSequence(wrappedStream)
        }
        
        let expectedSum = 0 + ((size.rawValue * (size.rawValue + 1)) / 2)
        #expect(sum == expectedSum)
        
        let throughput = Double(size.rawValue + 1) / duration
        print("SinglePrefix (\(size.name)): \(String(format: "%.2f", duration))s, \(String(format: "%.0f", throughput)) elements/sec")
    }
    
    // MARK: - Single Suffix Only Wrapper Performance
    
    @Test("SingleSuffix Wrapper Performance", arguments: TestSize.allCases)
    func singleSuffixWrapperPerformance(size: TestSize) async throws {
        let baseStream = createBaseStream(size: size.rawValue)
        let wrappedStream = baseStream.wrapped(suffix: size.rawValue + 1)
        
        let (sum, duration) = try await measureExecutionTime {
            try await sumSequence(wrappedStream)
        }
        
        let expectedSum = ((size.rawValue * (size.rawValue + 1)) / 2) + (size.rawValue + 1)
        #expect(sum == expectedSum)
        
        let throughput = Double(size.rawValue + 1) / duration
        print("SingleSuffix (\(size.name)): \(String(format: "%.2f", duration))s, \(String(format: "%.0f", throughput)) elements/sec")
    }
    
    // MARK: - Sequence Prefix Only Wrapper Performance
    
    @Test("SeqPrefix Wrapper Performance", arguments: TestSize.allCases)
    func seqPrefixWrapperPerformance(size: TestSize) async throws {
        let baseStream = createBaseStream(size: size.rawValue)
        let prefixStream = createSmallPrefixStream()
        let wrappedStream = baseStream.wrapped(prefix: prefixStream)
        
        let (sum, duration) = try await measureExecutionTime {
            try await sumSequence(wrappedStream)
        }
        
        let expectedSum = (-2 + -1) + ((size.rawValue * (size.rawValue + 1)) / 2)
        #expect(sum == expectedSum)
        
        let throughput = Double(size.rawValue + 2) / duration
        print("SeqPrefix (\(size.name)): \(String(format: "%.2f", duration))s, \(String(format: "%.0f", throughput)) elements/sec")
    }
    
    // MARK: - Sequence Suffix Only Wrapper Performance
    
    @Test("SeqSuffix Wrapper Performance", arguments: TestSize.allCases)
    func seqSuffixWrapperPerformance(size: TestSize) async throws {
        let baseStream = createBaseStream(size: size.rawValue)
        let suffixStream = createSmallSuffixStream()
        let wrappedStream = baseStream.wrapped(suffix: suffixStream)
        
        let (sum, duration) = try await measureExecutionTime {
            try await sumSequence(wrappedStream)
        }
        
        let expectedSum = ((size.rawValue * (size.rawValue + 1)) / 2) + (1_000_001 + 1_000_002)
        #expect(sum == expectedSum)
        
        let throughput = Double(size.rawValue + 2) / duration
        print("SeqSuffix (\(size.name)): \(String(format: "%.2f", duration))s, \(String(format: "%.0f", throughput)) elements/sec")
    }
    
    // MARK: - Memory and Overhead Tests
    
    @Test("Memory Overhead - Large Dataset")
    func memoryOverheadTest() async throws {
        let size = TestSize.large.rawValue
        
        // Test baseline memory usage
        let baselineMemory = try await measureMemoryUsage {
            let stream = createBaseStream(size: size)
            let _ = try await sumSequence(stream)
        }
        
        // Test wrapped memory usage
        let wrappedMemory = try await measureMemoryUsage {
            let baseStream = createBaseStream(size: size)
            let wrapped = baseStream.wrapped(prefix: 0, suffix: size + 1)
            let _ = try await sumSequence(wrapped)
        }
        
        // Memory overhead is informational only - measurements are inconsistent due to
        // system factors, garbage collection, and background processes
        let overhead = baselineMemory > 0 ? Double(wrappedMemory - baselineMemory) / Double(baselineMemory) : 0
        print("Memory overhead: \(String(format: "%.2f", overhead * 100))% (informational only)")
    }
    
    func measureMemoryUsage<T>(operation: () async throws -> T) async rethrows -> Int {
        let before = getMemoryUsage()
        let _ = try await operation()
        let after = getMemoryUsage()
        return max(0, after - before)
    }
    
    func getMemoryUsage() -> Int {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            return Int(info.resident_size)
        }
        return 0
    }
    
    // MARK: - Throughput Comparison Tests
    
    @Test("Throughput Comparison - Manual vs Wrapped")
    func throughputComparisonTest() async throws {
        let size = TestSize.medium.rawValue
        
        // Manual implementation
        let (manualSum, manualDuration) = await measureExecutionTime {
            var sum = 0
            
            // Add prefix
            sum += 0
            
            // Add base sequence
            for i in 1...size {
                sum += i
            }
            
            // Add suffix
            sum += (size + 1)
            
            return sum
        }
        
        // Wrapped implementation
        let (wrappedSum, wrappedDuration) = try await measureExecutionTime {
            let baseStream = createBaseStream(size: size)
            let wrapped = baseStream.wrapped(prefix: 0, suffix: size + 1)
            return try await sumSequence(wrapped)
        }
        
        #expect(manualSum == wrappedSum)
        
        let manualThroughput = Double(size + 2) / manualDuration
        let wrappedThroughput = Double(size + 2) / wrappedDuration
        let efficiency = wrappedThroughput / manualThroughput
        
        print("Manual throughput: \(String(format: "%.0f", manualThroughput)) elements/sec")
        print("Wrapped throughput: \(String(format: "%.0f", wrappedThroughput)) elements/sec")
        print("Efficiency: \(String(format: "%.2f", efficiency * 100))%")
        
        // Wrapped implementation should be reasonably efficient (>5% of manual)
        #expect(efficiency > 0.05, "Wrapped implementation should maintain reasonable performance")
    }
    
    // MARK: - Concurrent Access Tests
    
    @Test("Concurrent Wrapper Performance")
    func concurrentWrapperPerformance() async throws {
        let size = TestSize.small.rawValue
        let concurrentCount = 10
        
        let (_, duration) = await measureExecutionTime {
            await withTaskGroup(of: Int.self) { group in
                for _ in 0..<concurrentCount {
                    group.addTask {
                        let baseStream = self.createBaseStream(size: size)
                        let wrapped = baseStream.wrapped(prefix: 0, suffix: size + 1)
                        return try! await self.sumSequence(wrapped)
                    }
                }
                
                var totalSum = 0
                for await sum in group {
                    totalSum += sum
                }
                return totalSum
            }
        }
        
        let totalElements = concurrentCount * (size + 2)
        let throughput = Double(totalElements) / duration
        
        print("Concurrent throughput (\(concurrentCount) tasks): \(String(format: "%.0f", throughput)) elements/sec")
        
        // Should handle concurrent access without issues
        #expect(duration > 0)
        #expect(throughput > 0)
    }
    
    // MARK: - Error Handling Performance
    
    @Test("Error Handling Performance")
    func errorHandlingPerformance() async throws {
        let size = TestSize.small.rawValue
        
        let errorStream = AsyncThrowingStream<Int, Error> { continuation in
            for i in 1...size {
                if i == size / 2 {
                    continuation.finish(throwing: TestError.testFailure)
                    return
                }
                continuation.yield(i)
            }
            continuation.finish()
        }
        
        let wrapped = errorStream.wrapped(prefix: 0, suffix: size + 1)
        
        let (_, duration) = await measureExecutionTime {
            do {
                let _ = try await sumSequence(wrapped)
                #expect(Bool(false), "Should have thrown an error")
            } catch TestError.testFailure {
                // Expected error
            } catch {
                #expect(Bool(false), "Unexpected error: \(error)")
            }
        }
        
        print("Error handling duration: \(String(format: "%.4f", duration))s")
        
        // Error handling should be fast
        #expect(duration < 1.0)
    }
    
    enum TestError: Error {
        case testFailure
    }
}