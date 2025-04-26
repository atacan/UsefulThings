import Foundation

public func runCommand(_ command: String, workingDirectory: String? = nil) throws -> String {
    let task = Process()
    let pipe = Pipe()

    task.standardOutput = pipe
    task.standardError = pipe
    task.arguments = ["-c", command]
    task.executableURL = URL(fileURLWithPath: "/bin/sh")
    task.standardInput = nil

    if let workingDirectory {
        task.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
    }

    try task.run()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8)!

    return output.trimmingCharacters(in: .whitespacesAndNewlines)
}