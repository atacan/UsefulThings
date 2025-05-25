//
// https://github.com/atacan
// 25.05.25
	


import Foundation

// MARK: - Error Handling

enum CommandError: Error, LocalizedError {
    case ffprobeNotFound
    case launchFailed(underlyingError: Error)
    case executionFailed(statusCode: Int32, output: String, errorOutput: String)

    var errorDescription: String? {
        switch self {
        case .ffprobeNotFound:
            return "ffprobe executable not found in common system or Homebrew paths. Please ensure it's installed (e.g., via Homebrew on macOS, or apt on Ubuntu) and in your system's PATH, or provide an absolute path."
        case .launchFailed(let error):
            return "Failed to launch command: \(error.localizedDescription)"
        case .executionFailed(let statusCode, let output, let errorOutput):
            var description = "Command exited with status \(statusCode)."
            if !output.isEmpty { description += "\nOutput: \(output)" }
            if !errorOutput.isEmpty { description += "\nError: \(errorOutput)" }
            return description
        }
    }
}

// MARK: - Command Execution Helper

/// Tries to find the ffprobe executable in common installation paths.
/// Returns the absolute path if found, otherwise nil.
private func findFfprobeExecutablePath() -> String? {
    let commonPaths = [
        "/usr/bin/ffprobe",           // Common Linux/Unix path (apt on Ubuntu)
        "/usr/local/bin/ffprobe",     // Common Homebrew path (Intel Mac, older setups)
        "/opt/homebrew/bin/ffprobe"   // Common Homebrew path (Apple Silicon Mac)
    ]

    for path in commonPaths {
        if FileManager.default.fileExists(atPath: path) {
            return path
        }
    }
    return nil
}

/// Runs an external command (like ffprobe) directly using its absolute path.
/// This approach is more robust for cross-platform scenarios and avoids shell PATH issues.
///
/// - Parameters:
///   - executablePath: The absolute path to the executable (e.g., /usr/bin/ffprobe).
///   - arguments: An array of strings representing the arguments to pass to the executable.
///   - workingDirectory: The working directory for the command.
/// - Throws: `CommandError` if the command fails to launch or exits with a non-zero status.
/// - Returns: The standard output of the command.
public func runExternalCommand(
    executablePath: String,
    arguments: [String],
    workingDirectory: String? = nil
) throws -> String {
    let task = Process()
    let outputPipe = Pipe()
    let errorPipe = Pipe()

    task.standardOutput = outputPipe
    task.standardError = errorPipe
    task.standardInput = nil // No input needed

    task.executableURL = URL(fileURLWithPath: executablePath)
    task.arguments = arguments

    if let workingDirectory {
        task.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
    }

    do {
        try task.run()
        task.waitUntilExit() // Wait for the process to complete

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

        let output = String(data: outputData, encoding: .utf8) ?? ""
        let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

        if task.terminationStatus != 0 {
            throw CommandError.executionFailed(statusCode: task.terminationStatus, output: output, errorOutput: errorOutput)
        }

        return output.trimmingCharacters(in: .whitespacesAndNewlines)

    } catch {
        throw CommandError.launchFailed(underlyingError: error)
    }
}


// MARK: - ffprobe specific function

/// A convenience function specifically for running ffprobe.
/// It attempts to locate ffprobe on the system and then executes it.
///
/// - Parameters:
///   - ffprobeArguments: An array of strings representing the arguments to pass to ffprobe.
///   - workingDirectory: The working directory for the ffprobe command.
/// - Throws: `CommandError` if ffprobe is not found, fails to launch, or exits with a non-zero status.
/// - Returns: The standard output of the ffprobe command.
public func runFfprobe(
    ffprobeArguments: [String],
    workingDirectory: String? = nil
) throws -> String {
    guard let ffprobePath = findFfprobeExecutablePath() else {
        throw CommandError.ffprobeNotFound
    }

    return try runExternalCommand(
        executablePath: ffprobePath,
        arguments: ffprobeArguments,
        workingDirectory: workingDirectory
    )
}

// MARK: - Example Usage

// Assuming 'input.mp4' exists in your project's current directory or a known path
// For testing, you might need to create a dummy video file or use a path to an existing one.

// Example: Get video width and height
//let argumentsForFfprobe = ["-v", "error", "-select_streams", "v:0", "-show_entries", "stream=width,height", "-of", "csv=p=0:s=x", "input.mp4"]
//
//do {
//    let output = try runFfprobe(ffprobeArguments: argumentsForFfprobe)
//    print("ffprobe output: \(output)") // e.g., "1920x1080"
//} catch {
//    print("Error running ffprobe: \(error.localizedDescription)")
//}
//
//// Example: Get duration
//let argumentsForDuration = ["-v", "error", "-show_entries", "format=duration", "-of", "default=noprint_wrappers=1:nokey=1", "input.mp4"]
//
//do {
//    let output = try runFfprobe(ffprobeArguments: argumentsForDuration)
//    print("ffprobe duration: \(output)") // e.g., "120.567"
//} catch {
//    print("Error getting duration: \(error.localizedDescription)")
//}
