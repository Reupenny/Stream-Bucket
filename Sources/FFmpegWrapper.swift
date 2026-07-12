import Foundation

class FFmpegWrapper {
    static let shared = FFmpegWrapper()
    
    // Attempt to locate ffmpeg
    func findFFmpeg() -> URL? {
        let paths = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"]
        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }
    
    func findFFprobe() -> URL? {
        let paths = ["/opt/homebrew/bin/ffprobe", "/usr/local/bin/ffprobe", "/usr/bin/ffprobe"]
        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }
    
    func checkFFmpeg() -> Bool {
        return findFFmpeg() != nil && findFFprobe() != nil
    }
    
    // Runs an ffmpeg command asynchronously and yields stdout/stderr
    func run(arguments: [String], onLog: @escaping (String) -> Void) async throws {
        guard let ffmpegURL = findFFmpeg() else {
            throw NSError(domain: "FFmpegWrapper", code: 1, userInfo: [NSLocalizedDescriptionKey: "ffmpeg not found"])
        }
        
        let process = Process()
        process.executableURL = ffmpegURL
        process.arguments = arguments
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe // ffmpeg writes most logs to stderr
        
        let outHandle = pipe.fileHandleForReading
        
        return try await withCheckedThrowingContinuation { continuation in
            outHandle.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    outHandle.readabilityHandler = nil
                    return
                }
                if let string = String(data: data, encoding: .utf8) {
                    DispatchQueue.main.async {
                        onLog(string)
                    }
                }
            }
            
            process.terminationHandler = { proc in
                if proc.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: NSError(domain: "FFmpegWrapper", code: Int(proc.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "ffmpeg exited with status \(proc.terminationStatus)"]))
                }
            }
            
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    func getDuration(input: URL) async throws -> Double {
        guard let ffprobeURL = findFFprobe() else {
            throw NSError(domain: "FFmpegWrapper", code: 1, userInfo: [NSLocalizedDescriptionKey: "ffprobe not found"])
        }
        
        let process = Process()
        process.executableURL = ffprobeURL
        process.arguments = [
            "-v", "error",
            "-show_entries", "format=duration",
            "-of", "default=noprint_wrappers=1:nokey=1",
            input.path
        ]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { proc in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8),
                   let duration = Double(output.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    continuation.resume(returning: duration)
                } else {
                    continuation.resume(throwing: NSError(domain: "FFmpegWrapper", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not parse duration"]))
                }
            }
            
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    // Extract a poster at 5 seconds
    func extractPoster(input: URL, output: URL, onLog: @escaping (String) -> Void) async throws {
        let args = [
            "-y",
            "-ss", "00:00:05",
            "-i", input.path,
            "-vframes", "1",
            "-q:v", "2",
            output.path
        ]
        try await run(arguments: args, onLog: onLog)
    }
    
    // Extract sprite sheet
    func extractSpriteSheet(input: URL, outputDir: URL, interval: Double, cols: Int, rows: Int, onLog: @escaping (String) -> Void) async throws {
        let outputPattern = outputDir.appendingPathComponent("sprites_%03d.jpg").path
        let args = [
            "-y",
            "-i", input.path,
            "-filter_complex", "fps=1/\(interval),scale=160:90,tile=\(cols)x\(rows)",
            outputPattern
        ]
        try await run(arguments: args, onLog: onLog)
    }
}
