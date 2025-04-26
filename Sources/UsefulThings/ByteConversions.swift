public func doubleToUInt8Array(_ value: Double) -> [UInt8] {
    withUnsafeBytes(of: value) { Array($0) }
}
