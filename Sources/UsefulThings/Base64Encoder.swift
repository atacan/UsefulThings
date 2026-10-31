private let base64Alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".utf8)

private func base64Bytes<Bytes>(_ bytes: Bytes) -> Bytes { bytes }

private func base64UTF8<String: StringProtocol>(_ string: String) -> String.UTF8View { string.utf8 }

/// Lazily encodes a source as standard, padded Base64 bytes.
///
/// Accepts bytes, byte sequences (including `Data`), strings, and synchronous or
/// asynchronous sequences of byte chunks, strings, characters, or bytes. Strings
/// and characters are encoded as UTF-8, without separators between elements.
///
/// Each output chunk is nonempty, contains at most `chunkSize` ASCII bytes, and
/// ends on a four-byte Base64 boundary. Only the final chunk can contain padding.
/// Concatenating the output is equivalent to encoding the concatenated input.
///
/// The encoder pulls input only during `next()`. It retains the current input
/// chunk's iterator, at most two pending input bytes, and one output buffer. It
/// never collects the entire source or copies an entire input chunk. Memory held
/// by the source and its current chunk is in addition to the output buffer.
/// Cancellation and upstream errors are propagated and terminate the iterator.
///
/// ```swift
/// let encoded = Base64Encoder("Hello, world!")
/// for try await chunk in encoded {
///     // Write the ASCII bytes to a file, socket, or request body.
/// }
///
/// // Also accepts FileHandle, AsyncSequence<Data>, AsyncSequence<ArraySlice<UInt8>>,
/// // [Data], [String], AsyncSequence<String>, and AsyncSequence<Character>.
/// ```
public struct Base64Encoder<Base: AsyncSequence, Bytes: Sequence>: AsyncSequence
where Bytes.Element == UInt8 {
    public typealias ByteChunk = ArraySlice<UInt8>
    public typealias Element = ByteChunk

    private let base: Base
    private let chunkSize: Int
    private let bytes: @Sendable (Base.Element) -> Bytes

    private init(
        _ base: Base,
        chunkSize: Int,
        bytes: @Sendable @escaping (Base.Element) -> Bytes
    ) {
        precondition(chunkSize >= 4 && chunkSize.isMultiple(of: 4),
                     "chunkSize must be a positive multiple of 4")
        self.base = base
        self.chunkSize = chunkSize
        self.bytes = bytes
    }

    /// Encodes an asynchronous sequence of byte chunks, such as `Data` or `[UInt8]`.
    /// - Parameter chunkSize: Maximum output bytes per chunk; a positive multiple of four.
    public init(_ base: Base, chunkSize: Int = 65_536) where Base.Element == Bytes {
        self.init(base, chunkSize: chunkSize, bytes: base64Bytes)
    }

    /// Encodes the concatenated UTF-8 contents of asynchronous string elements.
    public init(_ base: Base, chunkSize: Int = 65_536)
    where Base.Element: StringProtocol, Bytes == Base.Element.UTF8View {
        self.init(base, chunkSize: chunkSize, bytes: base64UTF8)
    }

    /// Encodes the UTF-8 bytes of asynchronous `String.Element` (`Character`) elements.
    public init(_ base: Base, chunkSize: Int = 65_536)
    where Base.Element == Character, Bytes == String.UTF8View {
        self.init(base, chunkSize: chunkSize, bytes: { String($0).utf8 })
    }

    /// Encodes an asynchronous sequence of individual bytes.
    public init(_ base: Base, chunkSize: Int = 65_536)
    where Base.Element == UInt8, Bytes == CollectionOfOne<UInt8> {
        self.init(base, chunkSize: chunkSize, bytes: { CollectionOfOne($0) })
    }

    /// Encodes a byte sequence, including `Data`, `[UInt8]`, or `ArraySlice<UInt8>`.
    public init(_ bytes: Bytes, chunkSize: Int = 65_536)
    where Base == Base64EncoderInput<CollectionOfOne<Bytes>> {
        self.init(Base64EncoderInput(CollectionOfOne(bytes)), chunkSize: chunkSize, bytes: base64Bytes)
    }

    /// Encodes a string as UTF-8 without copying its full byte contents.
    public init(_ string: String, chunkSize: Int = 65_536)
    where Base == Base64EncoderInput<CollectionOfOne<String>>, Bytes == String.UTF8View {
        self.init(Base64EncoderInput(CollectionOfOne(string)), chunkSize: chunkSize, bytes: base64UTF8)
    }

    /// Encodes a substring as UTF-8 without copying its full byte contents.
    public init(_ string: Substring, chunkSize: Int = 65_536)
    where Base == Base64EncoderInput<CollectionOfOne<Substring>>, Bytes == Substring.UTF8View {
        self.init(Base64EncoderInput(CollectionOfOne(string)), chunkSize: chunkSize, bytes: base64UTF8)
    }

    /// Encodes a synchronous sequence of byte chunks without collecting the source.
    public init<S: Sequence>(_ chunks: S, chunkSize: Int = 65_536)
    where Base == Base64EncoderInput<S>, Bytes == S.Element {
        self.init(Base64EncoderInput(chunks), chunkSize: chunkSize, bytes: base64Bytes)
    }

    /// Encodes the concatenated UTF-8 contents of a synchronous sequence of strings.
    public init<S: Sequence>(_ strings: S, chunkSize: Int = 65_536)
    where Base == Base64EncoderInput<S>, S.Element: StringProtocol, Bytes == S.Element.UTF8View {
        self.init(Base64EncoderInput(strings), chunkSize: chunkSize, bytes: base64UTF8)
    }

    /// Encodes a synchronous sequence of `String.Element` (`Character`) values as UTF-8.
    public init<S: Sequence>(_ characters: S, chunkSize: Int = 65_536)
    where Base == Base64EncoderInput<S>, S.Element == Character, Bytes == String.UTF8View {
        self.init(Base64EncoderInput(characters), chunkSize: chunkSize, bytes: { String($0).utf8 })
    }

    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(base: base.makeAsyncIterator(), chunkSize: chunkSize, bytes: bytes)
    }

    public struct AsyncIterator: AsyncIteratorProtocol {
        private var base: Base.AsyncIterator
        private let chunkSize: Int
        private let bytes: @Sendable (Base.Element) -> Bytes
        private var currentChunk: Bytes.Iterator?
        private var first: UInt8 = 0
        private var second: UInt8 = 0
        private var pendingCount = 0
        private var finished = false

        fileprivate init(
            base: Base.AsyncIterator,
            chunkSize: Int,
            bytes: @Sendable @escaping (Base.Element) -> Bytes
        ) {
            self.base = base
            self.chunkSize = chunkSize
            self.bytes = bytes
        }

        public mutating func next() async throws -> ByteChunk? {
            guard !finished else { return nil }

            do {
                try Task.checkCancellation()
                var output: [UInt8] = []

                while true {
                    if currentChunk != nil {
                        while output.count < chunkSize, let byte = currentChunk?.next() {
                            switch pendingCount {
                            case 0:
                                first = byte
                                pendingCount = 1
                            case 1:
                                second = byte
                                pendingCount = 2
                            default:
                                output.append(base64Alphabet[Int(first >> 2)])
                                output.append(base64Alphabet[Int((first & 0x03) << 4 | second >> 4)])
                                output.append(base64Alphabet[Int((second & 0x0F) << 2 | byte >> 6)])
                                output.append(base64Alphabet[Int(byte & 0x3F)])
                                pendingCount = 0
                            }
                        }

                        if output.count == chunkSize {
                            return output[...]
                        }

                        currentChunk = nil
                        // Yield available output before waiting for another input chunk.
                        if !output.isEmpty {
                            return output[...]
                        }
                    }

                    try Task.checkCancellation()
                    let chunk = try await base.next()
                    try Task.checkCancellation()
                    guard let chunk else {
                        finished = true
                        if pendingCount > 0 {
                            output.append(base64Alphabet[Int(first >> 2)])
                            output.append(base64Alphabet[Int((first & 0x03) << 4 | secondForPadding >> 4)])
                            output.append(pendingCount == 2 ? base64Alphabet[Int((second & 0x0F) << 2)] : 61)
                            output.append(61) // "="
                            pendingCount = 0
                        }
                        return output.isEmpty ? nil : output[...]
                    }
                    currentChunk = bytes(chunk).makeIterator()
                }
            } catch {
                finished = true
                currentChunk = nil
                pendingCount = 0
                throw error
            }
        }

        private var secondForPadding: UInt8 { pendingCount == 2 ? second : 0 }
    }
}

extension Base64Encoder: Sendable where Base: Sendable {}

/// The lazy synchronous-input adapter used by `Base64Encoder`'s convenience initializers.
/// Its generic type is inferred when constructing an encoder.
public struct Base64EncoderInput<Base: Sequence>: AsyncSequence {
    public typealias Element = Base.Element
    private let base: Base

    fileprivate init(_ base: Base) {
        self.base = base
    }

    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(base: base.makeIterator())
    }

    public struct AsyncIterator: AsyncIteratorProtocol {
        private var base: Base.Iterator

        fileprivate init(base: Base.Iterator) {
            self.base = base
        }

        public mutating func next() async -> Element? {
            base.next()
        }
    }
}

extension Base64EncoderInput: Sendable where Base: Sendable {}
