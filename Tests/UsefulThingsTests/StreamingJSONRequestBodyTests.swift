import Foundation
import Testing
import UsefulThings

@Suite("Streaming JSON request body examples")
struct StreamingJSONRequestBodyTests {
    @Test("Stream an audio file into a nested JSON string field",
          arguments: [0, 1, 2, 75_000, 75_001, 75_002])
    func transcriptionRequest(sampleCount: Int) async throws {
        // Fixture: mono, 16 kHz, signed 16-bit little-endian PCM of a 440 Hz tone.
        // The sample counts cover empty audio, both padding cases, and several file reads.
        let originalAudio = makePCMFixture(sampleCount: sampleCount)
        let audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".pcm")
        try originalAudio.write(to: audioURL)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        // Example client: open the file and construct the request body without reading it.
        let audioFile = try FileHandle(forReadingFrom: audioURL)
        defer { try? audioFile.close() }

        // The prefix opens input.audio.content's JSON string; the suffix closes it
        // and supplies the rest of the nested JSON object. Both are UTF-8 byte chunks.
        let prefix = ArraySlice(
            #"{"config":{"encoding":"LINEAR16","sampleRateHertz":16000,"languageCode":"en-US"},"input":{"audio":{"content":""#.utf8
        )
        let suffix = ArraySlice(
            #""},"enableTimestamps":true},"metadata":{"requestId":"streaming-example"}}"#.utf8
        )
        let body = Base64Encoder(audioFile, chunkSize: 4_096)
            .wrapped(prefix: prefix, suffix: suffix)

        // Pass `body` to an HTTP client's streaming request-body API with
        // Content-Type: application/json. Each iteration supplies the next wire bytes.
        // Nothing inserts separators, quotes, or newlines between Base64 chunks.
        #expect(try audioFile.offset() == 0)

        // Simulate the receiver. Only the test collects the body so it can parse JSON;
        // the client-side sequence above never collects the file or the request body.
        var receivedBody = Data()
        var chunkCount = 0
        var lastChunk: ArraySlice<UInt8>?
        for try await chunk in body {
            if chunkCount == 0 {
                #expect(chunk == prefix)
                #expect(try audioFile.offset() == 0, "Sending the prefix must not read audio")
            }
            receivedBody.append(contentsOf: chunk)
            lastChunk = chunk
            chunkCount += 1
        }
        #expect(lastChunk == suffix)
        if originalAudio.isEmpty {
            #expect(chunkCount == 2) // Prefix and suffix form an empty JSON string.
        } else if originalAudio.count > 65_536 {
            #expect(chunkCount > 3) // The audio arrived in multiple encoded chunks.
        }

        // Independent accuracy check against Foundation's complete-data encoder.
        var expectedBody = Data(prefix)
        expectedBody.append(originalAudio.base64EncodedData())
        expectedBody.append(contentsOf: suffix)
        #expect(receivedBody == expectedBody)

        // A normal JSON decoder sees one string value despite all the wire chunks.
        // Its Base64 Data strategy also reconstructs the original audio bytes.
        let decoder = JSONDecoder()
        decoder.dataDecodingStrategy = .base64
        let request = try decoder.decode(TranscriptionRequest.self, from: receivedBody)
        #expect(request.input.audio.content == originalAudio)
        #expect(request.config.encoding == "LINEAR16")
        #expect(request.config.sampleRateHertz == 16_000)
        #expect(request.config.languageCode == "en-US")
        #expect(request.input.enableTimestamps)
        #expect(request.metadata.requestId == "streaming-example")
    }

    private func makePCMFixture(sampleCount: Int) -> Data {
        var audio = Data()
        for index in 0..<sampleCount {
            let phase = 2 * Double.pi * 440 * Double(index) / 16_000
            var sample = Int16(sin(phase) * 8_192).littleEndian
            withUnsafeBytes(of: &sample) { audio.append(contentsOf: $0) }
        }
        return audio
    }
}

// Illustrative endpoint schema; no network request or transcription service is needed.
private struct TranscriptionRequest: Decodable {
    let config: Configuration
    let input: Input
    let metadata: Metadata

    struct Configuration: Decodable {
        let encoding: String
        let sampleRateHertz: Int
        let languageCode: String
    }

    struct Input: Decodable {
        let audio: Audio
        let enableTimestamps: Bool

        struct Audio: Decodable {
            let content: Data
        }
    }

    struct Metadata: Decodable {
        let requestId: String
    }
}
