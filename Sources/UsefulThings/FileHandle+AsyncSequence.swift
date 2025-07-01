import Foundation

extension FileHandle: @retroactive AsyncSequence {
    public typealias Element = ArraySlice<UInt8>

    public struct AsyncFileIterator: AsyncIteratorProtocol {
        private let fileHandle: FileHandle
        private let chunkSize: Int
        private var isClosed = false

        init(fileHandle: FileHandle, chunkSize: Int = 32_768) {
            self.fileHandle = fileHandle
            self.chunkSize = chunkSize
        }

        public mutating func next() async throws -> ArraySlice<UInt8>? {
            guard !isClosed else { return nil }

            let data = try fileHandle.read(upToCount: chunkSize)
            if data?.isEmpty ?? true {
                isClosed = true
                try fileHandle.close()
                return nil
            }

            return ArraySlice(data!)
        }
    }

    public func makeAsyncIterator() -> AsyncFileIterator {
        AsyncFileIterator(fileHandle: self)
    }
}