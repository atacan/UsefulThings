import Testing
@testable import UsefulThings
import Foundation

@Suite("AsyncSequence Wrappers Correctness Tests")
struct AsyncSequenceWrappersCorrectnessTests {
    
    // MARK: - Helper Functions
    
    func createBaseStream(elements: [Int]) -> AsyncStream<Int> {
        AsyncStream<Int> { continuation in
            for element in elements {
                continuation.yield(element)
            }
            continuation.finish()
        }
    }
    
    func createPrefixStream(elements: [Int]) -> AsyncStream<Int> {
        AsyncStream<Int> { continuation in
            for element in elements {
                continuation.yield(element)
            }
            continuation.finish()
        }
    }
    
    func createSuffixStream(elements: [Int]) -> AsyncStream<Int> {
        AsyncStream<Int> { continuation in
            for element in elements {
                continuation.yield(element)
            }
            continuation.finish()
        }
    }
    
    func collectElements<S: AsyncSequence>(_ sequence: S) async throws -> [S.Element] {
        var result: [S.Element] = []
        for try await element in sequence {
            result.append(element)
        }
        return result
    }
    
    // MARK: - Single-Single Wrapper Tests
    
    @Test("SingleSingle Wrapper - Basic Functionality")
    func singleSingleBasic() async throws {
        let baseStream = createBaseStream(elements: [1, 2, 3])
        let wrapped = baseStream.wrapped(prefix: 0, suffix: 4)
        
        let result = try await collectElements(wrapped)
        let expected = [0, 1, 2, 3, 4]
        
        #expect(result == expected)
    }
    
    @Test("SingleSingle Wrapper - Empty Base")
    func singleSingleEmptyBase() async throws {
        let baseStream = createBaseStream(elements: [])
        let wrapped = baseStream.wrapped(prefix: -1, suffix: 1)
        
        let result = try await collectElements(wrapped)
        let expected = [-1, 1]
        
        #expect(result == expected)
    }
    
    @Test("SingleSingle Wrapper - Single Base Element")
    func singleSingleSingleBase() async throws {
        let baseStream = createBaseStream(elements: [42])
        let wrapped = baseStream.wrapped(prefix: 10, suffix: 99)
        
        let result = try await collectElements(wrapped)
        let expected = [10, 42, 99]
        
        #expect(result == expected)
    }
    
    // MARK: - Sequence-Sequence Wrapper Tests
    
    @Test("SeqSeq Wrapper - Basic Functionality")
    func seqSeqBasic() async throws {
        let baseStream = createBaseStream(elements: [10, 20, 30])
        let prefixStream = createPrefixStream(elements: [1, 2])
        let suffixStream = createSuffixStream(elements: [40, 50])
        let wrapped = baseStream.wrapped(prefix: prefixStream, suffix: suffixStream)
        
        let result = try await collectElements(wrapped)
        let expected = [1, 2, 10, 20, 30, 40, 50]
        
        #expect(result == expected)
    }
    
    @Test("SeqSeq Wrapper - Empty Sequences")
    func seqSeqEmptySequences() async throws {
        let baseStream = createBaseStream(elements: [])
        let prefixStream = createPrefixStream(elements: [])
        let suffixStream = createSuffixStream(elements: [])
        let wrapped = baseStream.wrapped(prefix: prefixStream, suffix: suffixStream)
        
        let result = try await collectElements(wrapped)
        let expected: [Int] = []
        
        #expect(result == expected)
    }
    
    @Test("SeqSeq Wrapper - Empty Base Only")
    func seqSeqEmptyBaseOnly() async throws {
        let baseStream = createBaseStream(elements: [])
        let prefixStream = createPrefixStream(elements: [1, 2])
        let suffixStream = createSuffixStream(elements: [3, 4])
        let wrapped = baseStream.wrapped(prefix: prefixStream, suffix: suffixStream)
        
        let result = try await collectElements(wrapped)
        let expected = [1, 2, 3, 4]
        
        #expect(result == expected)
    }
    
    @Test("SeqSeq Wrapper - Empty Prefix and Suffix")
    func seqSeqEmptyPrefixSuffix() async throws {
        let baseStream = createBaseStream(elements: [5, 6, 7])
        let prefixStream = createPrefixStream(elements: [])
        let suffixStream = createSuffixStream(elements: [])
        let wrapped = baseStream.wrapped(prefix: prefixStream, suffix: suffixStream)
        
        let result = try await collectElements(wrapped)
        let expected = [5, 6, 7]
        
        #expect(result == expected)
    }
    
    // MARK: - Single-Sequence Wrapper Tests
    
    @Test("SingleSeq Wrapper - Basic Functionality")
    func singleSeqBasic() async throws {
        let baseStream = createBaseStream(elements: [10, 20])
        let suffixStream = createSuffixStream(elements: [30, 40, 50])
        let wrapped = baseStream.wrapped(prefix: 5, suffix: suffixStream)
        
        let result = try await collectElements(wrapped)
        let expected = [5, 10, 20, 30, 40, 50]
        
        #expect(result == expected)
    }
    
    @Test("SingleSeq Wrapper - Empty Base")
    func singleSeqEmptyBase() async throws {
        let baseStream = createBaseStream(elements: [])
        let suffixStream = createSuffixStream(elements: [1, 2, 3])
        let wrapped = baseStream.wrapped(prefix: 0, suffix: suffixStream)
        
        let result = try await collectElements(wrapped)
        let expected = [0, 1, 2, 3]
        
        #expect(result == expected)
    }
    
    @Test("SingleSeq Wrapper - Empty Suffix")
    func singleSeqEmptySuffix() async throws {
        let baseStream = createBaseStream(elements: [10, 20])
        let suffixStream = createSuffixStream(elements: [])
        let wrapped = baseStream.wrapped(prefix: 5, suffix: suffixStream)
        
        let result = try await collectElements(wrapped)
        let expected = [5, 10, 20]
        
        #expect(result == expected)
    }
    
    // MARK: - Sequence-Single Wrapper Tests
    
    @Test("SeqSingle Wrapper - Basic Functionality")
    func seqSingleBasic() async throws {
        let baseStream = createBaseStream(elements: [20, 30])
        let prefixStream = createPrefixStream(elements: [5, 10, 15])
        let wrapped = baseStream.wrapped(prefix: prefixStream, suffix: 40)
        
        let result = try await collectElements(wrapped)
        let expected = [5, 10, 15, 20, 30, 40]
        
        #expect(result == expected)
    }
    
    @Test("SeqSingle Wrapper - Empty Base")
    func seqSingleEmptyBase() async throws {
        let baseStream = createBaseStream(elements: [])
        let prefixStream = createPrefixStream(elements: [1, 2])
        let wrapped = baseStream.wrapped(prefix: prefixStream, suffix: 99)
        
        let result = try await collectElements(wrapped)
        let expected = [1, 2, 99]
        
        #expect(result == expected)
    }
    
    @Test("SeqSingle Wrapper - Empty Prefix")
    func seqSingleEmptyPrefix() async throws {
        let baseStream = createBaseStream(elements: [10, 20])
        let prefixStream = createPrefixStream(elements: [])
        let wrapped = baseStream.wrapped(prefix: prefixStream, suffix: 30)
        
        let result = try await collectElements(wrapped)
        let expected = [10, 20, 30]
        
        #expect(result == expected)
    }
    
    // MARK: - Single Prefix Only Wrapper Tests
    
    @Test("SinglePrefix Wrapper - Basic Functionality")
    func singlePrefixBasic() async throws {
        let baseStream = createBaseStream(elements: [10, 20, 30])
        let wrapped = baseStream.wrapped(prefix: 5)
        
        let result = try await collectElements(wrapped)
        let expected = [5, 10, 20, 30]
        
        #expect(result == expected)
    }
    
    @Test("SinglePrefix Wrapper - Empty Base")
    func singlePrefixEmptyBase() async throws {
        let baseStream = createBaseStream(elements: [])
        let wrapped = baseStream.wrapped(prefix: 42)
        
        let result = try await collectElements(wrapped)
        let expected = [42]
        
        #expect(result == expected)
    }
    
    @Test("SinglePrefix Wrapper - Single Base Element")
    func singlePrefixSingleBase() async throws {
        let baseStream = createBaseStream(elements: [100])
        let wrapped = baseStream.wrapped(prefix: 50)
        
        let result = try await collectElements(wrapped)
        let expected = [50, 100]
        
        #expect(result == expected)
    }
    
    // MARK: - Single Suffix Only Wrapper Tests
    
    @Test("SingleSuffix Wrapper - Basic Functionality")
    func singleSuffixBasic() async throws {
        let baseStream = createBaseStream(elements: [1, 2, 3])
        let wrapped = baseStream.wrapped(suffix: 99)
        
        let result = try await collectElements(wrapped)
        let expected = [1, 2, 3, 99]
        
        #expect(result == expected)
    }
    
    @Test("SingleSuffix Wrapper - Empty Base")
    func singleSuffixEmptyBase() async throws {
        let baseStream = createBaseStream(elements: [])
        let wrapped = baseStream.wrapped(suffix: 42)
        
        let result = try await collectElements(wrapped)
        let expected = [42]
        
        #expect(result == expected)
    }
    
    @Test("SingleSuffix Wrapper - Single Base Element")
    func singleSuffixSingleBase() async throws {
        let baseStream = createBaseStream(elements: [10])
        let wrapped = baseStream.wrapped(suffix: 20)
        
        let result = try await collectElements(wrapped)
        let expected = [10, 20]
        
        #expect(result == expected)
    }
    
    // MARK: - Sequence Prefix Only Wrapper Tests
    
    @Test("SeqPrefix Wrapper - Basic Functionality")
    func seqPrefixBasic() async throws {
        let baseStream = createBaseStream(elements: [30, 40, 50])
        let prefixStream = createPrefixStream(elements: [10, 20])
        let wrapped = baseStream.wrapped(prefix: prefixStream)
        
        let result = try await collectElements(wrapped)
        let expected = [10, 20, 30, 40, 50]
        
        #expect(result == expected)
    }
    
    @Test("SeqPrefix Wrapper - Empty Base")
    func seqPrefixEmptyBase() async throws {
        let baseStream = createBaseStream(elements: [])
        let prefixStream = createPrefixStream(elements: [1, 2, 3])
        let wrapped = baseStream.wrapped(prefix: prefixStream)
        
        let result = try await collectElements(wrapped)
        let expected = [1, 2, 3]
        
        #expect(result == expected)
    }
    
    @Test("SeqPrefix Wrapper - Empty Prefix")
    func seqPrefixEmptyPrefix() async throws {
        let baseStream = createBaseStream(elements: [10, 20])
        let prefixStream = createPrefixStream(elements: [])
        let wrapped = baseStream.wrapped(prefix: prefixStream)
        
        let result = try await collectElements(wrapped)
        let expected = [10, 20]
        
        #expect(result == expected)
    }
    
    // MARK: - Sequence Suffix Only Wrapper Tests
    
    @Test("SeqSuffix Wrapper - Basic Functionality")
    func seqSuffixBasic() async throws {
        let baseStream = createBaseStream(elements: [1, 2])
        let suffixStream = createSuffixStream(elements: [3, 4, 5])
        let wrapped = baseStream.wrapped(suffix: suffixStream)
        
        let result = try await collectElements(wrapped)
        let expected = [1, 2, 3, 4, 5]
        
        #expect(result == expected)
    }
    
    @Test("SeqSuffix Wrapper - Empty Base")
    func seqSuffixEmptyBase() async throws {
        let baseStream = createBaseStream(elements: [])
        let suffixStream = createSuffixStream(elements: [10, 20, 30])
        let wrapped = baseStream.wrapped(suffix: suffixStream)
        
        let result = try await collectElements(wrapped)
        let expected = [10, 20, 30]
        
        #expect(result == expected)
    }
    
    @Test("SeqSuffix Wrapper - Empty Suffix")
    func seqSuffixEmptySuffix() async throws {
        let baseStream = createBaseStream(elements: [5, 6, 7])
        let suffixStream = createSuffixStream(elements: [])
        let wrapped = baseStream.wrapped(suffix: suffixStream)
        
        let result = try await collectElements(wrapped)
        let expected = [5, 6, 7]
        
        #expect(result == expected)
    }
    
    // MARK: - Error Propagation Tests
    
    @Test("Error Propagation - Base Stream Throws")
    func errorInBaseStream() async throws {
        let errorStream = AsyncThrowingStream<Int, Error> { continuation in
            continuation.yield(1)
            continuation.yield(2)
            continuation.finish(throwing: TestError.baseStreamError)
        }
        
        let wrapped = errorStream.wrapped(prefix: 0, suffix: 99)
        
        do {
            let _ = try await collectElements(wrapped)
            #expect(Bool(false), "Should have thrown an error")
        } catch TestError.baseStreamError {
            // Expected error
        } catch {
            #expect(Bool(false), "Unexpected error: \(error)")
        }
    }
    
    @Test("Error Propagation - Prefix Stream Throws")
    func errorInPrefixStream() async throws {
        let baseStream = createBaseStream(elements: [10, 20])
        
        let errorPrefixStream = AsyncThrowingStream<Int, Error> { continuation in
            continuation.yield(1)
            continuation.finish(throwing: TestError.prefixStreamError)
        }
        
        let wrapped = baseStream.wrapped(prefix: errorPrefixStream, suffix: 99)
        
        do {
            let _ = try await collectElements(wrapped)
            #expect(Bool(false), "Should have thrown an error")
        } catch TestError.prefixStreamError {
            // Expected error
        } catch {
            #expect(Bool(false), "Unexpected error: \(error)")
        }
    }
    
    @Test("Error Propagation - Suffix Stream Throws")
    func errorInSuffixStream() async throws {
        let baseStream = createBaseStream(elements: [10, 20])
        
        let errorSuffixStream = AsyncThrowingStream<Int, Error> { continuation in
            continuation.yield(30)
            continuation.finish(throwing: TestError.suffixStreamError)
        }
        
        let wrapped = baseStream.wrapped(prefix: 5, suffix: errorSuffixStream)
        
        do {
            let _ = try await collectElements(wrapped)
            #expect(Bool(false), "Should have thrown an error")
        } catch TestError.suffixStreamError {
            // Expected error
        } catch {
            #expect(Bool(false), "Unexpected error: \(error)")
        }
    }
    
    // MARK: - Large Dataset Tests
    
    @Test("Large Dataset - Correct Ordering")
    func largeDatasetOrdering() async throws {
        let baseElements = Array(100...199)  // 100 elements
        let prefixElements = Array(1...49)   // 49 elements  
        let suffixElements = Array(200...249) // 50 elements
        
        let baseStream = createBaseStream(elements: baseElements)
        let prefixStream = createPrefixStream(elements: prefixElements)
        let suffixStream = createSuffixStream(elements: suffixElements)
        
        let wrapped = baseStream.wrapped(prefix: prefixStream, suffix: suffixStream)
        
        let result = try await collectElements(wrapped)
        let expected = prefixElements + baseElements + suffixElements
        
        #expect(result == expected)
        #expect(result.count == 199) // 49 + 100 + 50
    }
    
    @Test("Large Dataset - Single Elements")
    func largeDatasetSingleElements() async throws {
        let baseElements = Array(1...1000)
        let baseStream = createBaseStream(elements: baseElements)
        
        let wrapped = baseStream.wrapped(prefix: 0, suffix: 1001)
        
        let result = try await collectElements(wrapped)
        let expected = [0] + baseElements + [1001]
        
        #expect(result == expected)
        #expect(result.count == 1002)
        #expect(result.first == 0)
        #expect(result.last == 1001)
    }
    
    // MARK: - Multiple Wrapping Tests
    
    @Test("Multiple Wrapping - Nested Wrappers")
    func multipleWrapping() async throws {
        let baseStream = createBaseStream(elements: [10, 20])
        
        // First wrap with prefix and suffix
        let firstWrapped = baseStream.wrapped(prefix: 5, suffix: 25)
        
        // Then wrap again
        let secondWrapped = firstWrapped.wrapped(prefix: 0, suffix: 30)
        
        let result = try await collectElements(secondWrapped)
        let expected = [0, 5, 10, 20, 25, 30]
        
        #expect(result == expected)
    }
    
    // MARK: - Type Consistency Tests
    
    @Test("String Elements - Correct Ordering")
    func stringElementsOrdering() async throws {
        let baseStream = AsyncStream<String> { continuation in
            continuation.yield("base1")
            continuation.yield("base2")
            continuation.finish()
        }
        
        let prefixStream = AsyncStream<String> { continuation in
            continuation.yield("prefix1")
            continuation.yield("prefix2")
            continuation.finish()
        }
        
        let suffixStream = AsyncStream<String> { continuation in
            continuation.yield("suffix1")
            continuation.yield("suffix2")
            continuation.finish()
        }
        
        let wrapped = baseStream.wrapped(prefix: prefixStream, suffix: suffixStream)
        
        let result = try await collectElements(wrapped)
        let expected = ["prefix1", "prefix2", "base1", "base2", "suffix1", "suffix2"]
        
        #expect(result == expected)
    }
    
    enum TestError: Error {
        case baseStreamError
        case prefixStreamError
        case suffixStreamError
    }
}