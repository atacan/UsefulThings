import Foundation
import Testing
import UsefulThings

@Suite("Streaming Base64 encoder")
struct Base64EncoderTests {
    private func collect<S: AsyncSequence>(_ sequence: S) async throws -> [UInt8]
    where S.Element == ArraySlice<UInt8> {
        var result: [UInt8] = []
        for try await chunk in sequence {
            #expect(!chunk.isEmpty)
            #expect(chunk.count.isMultiple(of: 4))
            result.append(contentsOf: chunk)
        }
        return result
    }

    @Test("Standard Base64 vectors", arguments: [
        ("", ""), ("f", "Zg=="), ("fo", "Zm8="), ("foo", "Zm9v"),
        ("foob", "Zm9vYg=="), ("fooba", "Zm9vYmE="), ("foobar", "Zm9vYmFy"),
    ])
    func standardVectors(input: String, expected: String) async throws {
        let result = try await collect(Base64Encoder(input, chunkSize: 4))
        #expect(String(decoding: result, as: UTF8.self) == expected)
    }

    @Test("Single Data, byte sequence, slice, string, and substring inputs")
    func singleInputs() async throws {
        let string = "Grüße 👩🏽‍💻 e\u{301} 日本語"
        let data = Data(string.utf8)
        let expected = Array(data.base64EncodedData())
        #expect(try await collect(Base64Encoder(data)) == expected)
        #expect(try await collect(Base64Encoder(Array(data))) == expected)
        #expect(try await collect(Base64Encoder(AnySequence(data))) == expected)
        #expect(try await collect(Base64Encoder(string)) == expected)

        let padded = [UInt8(255)] + Array(data) + [255]
        #expect(try await collect(Base64Encoder(padded[1..<padded.count - 1])) == expected)
        let substring = ("!" + string).dropFirst()
        #expect(try await collect(Base64Encoder(substring)) == expected)
    }

    @Test("Synchronous chunk, string, and character inputs")
    func synchronousInputs() async throws {
        let strings = ["", "f", "", "o", "oba", "r", " 👩🏽‍💻", "e\u{301}"]
        let expected = Array(Data(strings.joined().utf8).base64EncodedData())
        #expect(try await collect(Base64Encoder(strings)) == expected)
        #expect(try await collect(Base64Encoder(strings.lazy.map { $0[...] })) == expected)
        #expect(try await collect(Base64Encoder(strings.map { Data($0.utf8) })) == expected)
        #expect(try await collect(Base64Encoder(strings.map { Array($0.utf8) })) == expected)
        #expect(try await collect(Base64Encoder(strings.map { Array($0.utf8)[...] })) == expected)
        #expect(try await collect(Base64Encoder(Array(strings.joined()))) == expected)
    }

    @Test("Asynchronous chunk, string, character, and byte inputs")
    func asynchronousInputs() async throws {
        let strings = ["", "f", "o", "", "ob", "ar", " 🐦", "e\u{301}"]
        let expected = Array(Data(strings.joined().utf8).base64EncodedData())
        #expect(try await collect(Base64Encoder(AsyncValues(strings))) == expected)
        #expect(try await collect(Base64Encoder(AsyncValues(strings.map { $0[...] }))) == expected)
        #expect(try await collect(Base64Encoder(AsyncValues(strings.map { Data($0.utf8) }))) == expected)
        #expect(try await collect(Base64Encoder(AsyncValues(strings.map { Array($0.utf8) }))) == expected)
        #expect(try await collect(Base64Encoder(AsyncValues(strings.map { Array($0.utf8)[...] }))) == expected)
        #expect(try await collect(Base64Encoder(AsyncValues(Array(strings.joined())))) == expected)
        #expect(try await collect(Base64Encoder(AsyncValues(Array(strings.joined().utf8)))) == expected)
    }

    @Test("Binary data is independent of input and output chunk boundaries",
          arguments: [1, 2, 3, 4, 5, 7, 64, 257], [4, 8, 64, 65_536])
    func chunkBoundaries(inputChunkSize: Int, outputChunkSize: Int) async throws {
        // Includes every possible byte, multiple padding cases, and nonzero slice indices.
        for length in [0, 1, 2, 3, 255, 256, 257, 1_027] {
            let bytes = (0..<length).map { UInt8(truncatingIfNeeded: $0 * 73) }
            var chunks: [ArraySlice<UInt8>] = [[]]
            for offset in stride(from: 0, to: bytes.count, by: inputChunkSize) {
                chunks.append(bytes[offset..<min(offset + inputChunkSize, bytes.count)])
                chunks.append([])
            }
            var encoded: [UInt8] = []
            for try await chunk in Base64Encoder(AsyncValues(chunks), chunkSize: outputChunkSize) {
                #expect(!chunk.isEmpty && chunk.count <= outputChunkSize)
                #expect(chunk.count.isMultiple(of: 4))
                encoded.append(contentsOf: chunk)
            }
            #expect(encoded == Array(Data(bytes).base64EncodedData()))
        }
    }

    #if os(macOS)
    @Test("Output exactly matches the macOS base64 CLI",
          arguments: [0, 1, 2, 3, 255, 256, 257, 65_535, 65_536, 65_537, 150_001])
    func macOSCLIAccuracy(length: Int) async throws {
        // Reproducible binary input, independent of Foundation's Base64 implementation.
        var seed: UInt64 = 0x4D59_5DF4_D0F3_3173
        let input = Data((0..<length).map { _ in
            seed = seed &* 2_862_933_555_777_941_757 &+ 3_037_000_493
            return UInt8(truncatingIfNeeded: seed >> 32)
        })
        let expected = try base64UsingCLI(input)

        // Exercise carry bytes, empty chunks, and chunks larger than the output limit.
        let widths = [1, 2, 5, 17, 1_021, 65_537]
        var chunks: [Data] = [Data()]
        var offset = 0
        var widthIndex = 0
        while offset < input.count {
            let end = min(offset + widths[widthIndex % widths.count], input.count)
            chunks.append(input[offset..<end])
            chunks.append(Data())
            offset = end
            widthIndex += 1
        }

        for chunkSize in [4, 64, 65_536] {
            let encoded = Data(try await collect(Base64Encoder(AsyncValues(chunks), chunkSize: chunkSize)))
            #expect(encoded == expected, "CLI mismatch for input length \(length), output limit \(chunkSize)")
            let decoded = try base64UsingCLI(encoded, decode: true)
            #expect(decoded == input, "CLI failed to round-trip the streaming encoder's output")
        }
    }

    @Test("Unicode strings and characters exactly match the macOS base64 CLI")
    func macOSCLIUnicodeAccuracy() async throws {
        let strings = ["", "Grüße", " 👩🏽‍💻", " e\u{301}", " 日本語", "\0\n", ""]
        let text = strings.joined()
        let expected = Array(try base64UsingCLI(Data(text.utf8)))
        #expect(try await collect(Base64Encoder(text, chunkSize: 4)) == expected)
        #expect(try await collect(Base64Encoder(AsyncValues(strings), chunkSize: 4)) == expected)
        #expect(try await collect(Base64Encoder(AsyncValues(Array(text)), chunkSize: 4)) == expected)
    }

    private func base64UsingCLI(_ input: Data, decode: Bool = false) throws -> Data {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let inputURL = directory.appendingPathComponent("input")
        let outputURL = directory.appendingPathComponent("output")
        try input.write(to: inputURL)

        // File arguments avoid pipe-buffer deadlocks with larger fixtures.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/base64")
        process.arguments = (decode ? ["-D"] : ["-b", "0"])
            + ["-i", inputURL.path, "-o", outputURL.path]
        try process.run()
        process.waitUntilExit()
        try #require(process.terminationReason == .exit && process.terminationStatus == 0,
                     "macOS base64 CLI failed with status \(process.terminationStatus)")

        var output = try Data(contentsOf: outputURL)
        // Even with wrapping disabled, macOS base64 appends one presentation newline.
        // Remove only that newline from encoded output; decoded binary is untouched.
        if !decode && output.last == 0x0A { output.removeLast() }
        return output
    }
    #endif

    @Test("All-empty inputs yield no output")
    func emptyInputs() async throws {
        #expect(try await collect(Base64Encoder(Data())).isEmpty)
        #expect(try await collect(Base64Encoder([Data(), Data()])).isEmpty)
        #expect(try await collect(Base64Encoder([String]())).isEmpty)
        let emptyStrings = try await collect(Base64Encoder(AsyncValues(["", ""])))
        #expect(emptyStrings.isEmpty)
        #expect(try await collect(Base64Encoder(AsyncValues([UInt8]()))).isEmpty)
        #expect(try await collect(Base64Encoder(AsyncValues([Character]()))).isEmpty)
    }

    @Test("An infinite byte source is pulled only far enough to produce one bounded chunk")
    func lazyInfiniteInput() async throws {
        let counts = PullCounts()
        let input = ObservedBytes(counts: counts)
        let encoder = Base64Encoder(input, chunkSize: 8)
        #expect(counts.iterators == 0 && counts.reads == 0)
        var iterator = encoder.makeAsyncIterator()
        #expect(counts.iterators == 0 && counts.reads == 0)

        let first = try #require(await iterator.next())
        #expect(counts.iterators == 1 && counts.reads == 6)
        #expect(Array(first) == Array(Data([0, 1, 2, 3, 4, 5]).base64EncodedData()))
        let second = try #require(await iterator.next())
        #expect(counts.reads == 12)
        #expect(Array(second) == Array(Data([6, 7, 8, 9, 10, 11]).base64EncodedData()))
        #expect(Array(first) == Array(Data([0, 1, 2, 3, 4, 5]).base64EncodedData()))
    }

    @Test("Available output is yielded before pulling another asynchronous chunk")
    func noReadAhead() async throws {
        let counts = PullCounts()
        let input = ObservedChunks(chunks: [Array("foo".utf8)], counts: counts, failAtEnd: true)
        let encoder = Base64Encoder(input)
        #expect(counts.iterators == 0 && counts.reads == 0)
        var iterator = encoder.makeAsyncIterator()
        #expect(counts.iterators == 1 && counts.reads == 0)
        let output = try #require(await iterator.next())
        #expect(String(decoding: output, as: UTF8.self) == "Zm9v")
        #expect(counts.reads == 1)
        await #expect(throws: InputError.failed) { try await iterator.next() }
        #expect(try await iterator.next() == nil)
        #expect(counts.reads == 2)
    }

    @Test("An upstream error does not emit padded partial input", arguments: [1, 2])
    func upstreamError(pendingBytes: Int) async throws {
        let counts = PullCounts()
        let input = ObservedChunks(chunks: [Array(repeating: 102, count: pendingBytes)],
                                   counts: counts, failAtEnd: true)
        var iterator = Base64Encoder(input).makeAsyncIterator()
        await #expect(throws: InputError.failed) { try await iterator.next() }
        #expect(try await iterator.next() == nil)
        #expect(counts.reads == 2)
    }

    @Test("Padding and end of sequence are emitted only once")
    func terminalState() async throws {
        let counts = PullCounts()
        var iterator = Base64Encoder(ObservedChunks(chunks: [[102]], counts: counts)).makeAsyncIterator()
        let output = try #require(await iterator.next())
        #expect(String(decoding: output, as: UTF8.self) == "Zg==")
        #expect(try await iterator.next() == nil)
        #expect(try await iterator.next() == nil)
        #expect(counts.reads == 2)
    }

    @Test("Separate iterators retain independent encoding state")
    func independentIterators() async throws {
        let encoder = Base64Encoder("foobar!", chunkSize: 4)
        var first = encoder.makeAsyncIterator()
        var second = encoder.makeAsyncIterator()
        #expect(try await first.next() == second.next())
        #expect(try await first.next() == second.next())
        #expect(try await first.next() == second.next())
        #expect(try await first.next() == nil)
        #expect(try await second.next() == nil)
    }

    @Test("Cancellation stops buffered input without further reads")
    func cancellation() async throws {
        try await Task { () async throws -> Void in
            let counts = PullCounts()
            var iterator = Base64Encoder(ObservedBytes(counts: counts), chunkSize: 4).makeAsyncIterator()
            #expect(try await iterator.next() != nil)
            #expect(counts.reads == 3)
            withUnsafeCurrentTask { $0?.cancel() }
            await #expect(throws: CancellationError.self) { try await iterator.next() }
            #expect(try await iterator.next() == nil)
            #expect(counts.reads == 3)
        }.value
    }

    @Test("FileHandle input streams through multiple output chunks")
    func fileInput() async throws {
        let data = Data((0..<150_001).map { UInt8(truncatingIfNeeded: $0) })
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        #expect(try await collect(Base64Encoder(handle)) == Array(data.base64EncodedData()))
    }
}

private struct AsyncValues<Base: Sequence>: AsyncSequence {
    let base: Base

    init(_ base: Base) { self.base = base }

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(base: base.makeIterator())
    }

    struct AsyncIterator: AsyncIteratorProtocol {
        var base: Base.Iterator
        mutating func next() async -> Base.Element? { base.next() }
    }
}

private final class PullCounts {
    var iterators = 0
    var reads = 0
}

private struct ObservedBytes: Sequence {
    let counts: PullCounts

    func makeIterator() -> Iterator {
        counts.iterators += 1
        return Iterator(counts: counts)
    }

    struct Iterator: IteratorProtocol {
        let counts: PullCounts
        mutating func next() -> UInt8? {
            defer { counts.reads += 1 }
            return UInt8(truncatingIfNeeded: counts.reads)
        }
    }
}

private enum InputError: Error { case failed }

private struct ObservedChunks: AsyncSequence {
    let chunks: [[UInt8]]
    let counts: PullCounts
    var failAtEnd = false

    func makeAsyncIterator() -> AsyncIterator {
        counts.iterators += 1
        return AsyncIterator(chunks: chunks.makeIterator(), counts: counts, failAtEnd: failAtEnd)
    }

    struct AsyncIterator: AsyncIteratorProtocol {
        var chunks: IndexingIterator<[[UInt8]]>
        let counts: PullCounts
        let failAtEnd: Bool

        mutating func next() async throws -> [UInt8]? {
            counts.reads += 1
            if let chunk = chunks.next() { return chunk }
            if failAtEnd { throw InputError.failed }
            return nil
        }
    }
}
