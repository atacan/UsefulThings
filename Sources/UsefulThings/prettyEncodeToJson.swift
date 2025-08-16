import Foundation

public func prettyEncode<T: Encodable>(_ thing: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted]
    let data = try encoder.encode(thing)
    return data
}