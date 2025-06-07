import Foundation

public func getEnvironmentVariable(_ name: String, from envFileUrl: URL) -> String? {
    if let value = ProcessInfo.processInfo.environment[name] {
        return value
    }

    let dotenvData = try! Data(contentsOf: envFileUrl)
    let dotenvString = String(data: dotenvData, encoding: .utf8)!
    let dotenvLines = dotenvString.split(separator: "\n")
    for line in dotenvLines {
        let parts = line.split(separator: "=")
        if parts[0] == name {
            return String(parts[1])
        }
    }
    return nil
}
