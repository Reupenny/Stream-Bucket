import Foundation
import SwiftUI
import Combine

@MainActor
class LiveServerProcess: ObservableObject {
    @Published var isRunning = false
    @Published var logs: [LogEntry] = []
    @Published var clientConnected = false   // True when OBS/encoder has connected
    
    // Stats
    @Published var activeStreams: Int = 0
    @Published var totalBitrate: String = "0 Mbps"
    @Published var activeHLSOutputs: Int = 0
    @Published var viewers: Int = 0
    
    struct LogEntry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let level: String
        let thread: String
        let message: String
    }
    
    private var ffmpegProcess: Process?
    private var ffmpegPipe: Pipe?
    
    // S3 Background upload
    private var s3UploaderTask: Task<Void, Never>?
    private var outputDirURL: URL?
    
    func startServer(state: ProcessorState, streamTitle: String? = nil, streamKey: String? = nil) {
        guard !isRunning else { return }
        
        // 1. Create a persistent output directory (not temp – we need S3 uploader to keep finding files)
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            appendLog(level: "ERROR", thread: "Main", message: "Could not locate Application Support directory")
            return
        }
        let hlsDir = appSupport.appendingPathComponent("HLSBatchProcessor/live_output", isDirectory: true)
        do {
            // Clear any old segments first
            if FileManager.default.fileExists(atPath: hlsDir.path) {
                try FileManager.default.removeItem(at: hlsDir)
            }
            try FileManager.default.createDirectory(at: hlsDir, withIntermediateDirectories: true)
            self.outputDirURL = hlsDir
        } catch {
            appendLog(level: "ERROR", thread: "Main", message: "Failed to create output directory: \(error.localizedDescription)")
            return
        }
        
        // HLS playlist file (we will use master.m3u8 for consistency with embed URLs)
        let playlistPath = hlsDir.appendingPathComponent("master.m3u8").path
        
        let process = Process()
        guard let ffmpegURL = FFmpegWrapper.shared.findFFmpeg() else {
            appendLog(level: "ERROR", thread: "Main", message: "FFmpeg not found. Install via Homebrew: brew install ffmpeg")
            return
        }
        process.executableURL = ffmpegURL
        
        let trimmed = streamKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let listenKey = trimmed.isEmpty ? "stream" : trimmed
        let listenUrl = "rtmp://localhost:1935/live/\(listenKey)"
        
        var args = [
            "-listen", "1",
            "-i", listenUrl
        ]
        
        struct Resolution {
            let name: String
            let scale: String
            let bitrate: String
        }
        var selectedResolutions: [Resolution] = []
        if state.enable1080p { selectedResolutions.append(Resolution(name: "1080p", scale: "1920:1080", bitrate: "5000k")) }
        if state.enable720p  { selectedResolutions.append(Resolution(name: "720p",  scale: "1280:720",  bitrate: "2800k")) }
        if state.enable480p  { selectedResolutions.append(Resolution(name: "480p",  scale: "854:480",   bitrate: "1400k")) }
        if state.enable240p  { selectedResolutions.append(Resolution(name: "240p",  scale: "426:240",   bitrate: "400k"))  }
        
        // livePlaylistSize == 0 means "keep all segments" (event-style / VOD replayable)
        let hlsFlags = state.livePlaylistSize == 0
            ? "append_list+independent_segments"
            : "delete_segments+append_list+independent_segments"
        
        if selectedResolutions.isEmpty {
            // Direct copy (no ABR)
            args.append(contentsOf: [
                "-c:v", "copy",
                "-c:a", "aac",
                "-b:a", "128k",
                "-f", "hls",
                "-hls_time", "\(state.liveSegmentLength)",
                "-hls_list_size", "\(state.livePlaylistSize)",
                "-hls_flags", hlsFlags,
                "-hls_segment_type", "mpegts",
                "-hls_segment_filename", hlsDir.appendingPathComponent("segment_%05d.ts").path,
                playlistPath
            ])
        } else {
            // ABR encoding
            var filterComplex = "[0:v]split=\(selectedResolutions.count)"
            for i in 0..<selectedResolutions.count { filterComplex += "[v\(i)]" }
            filterComplex += "; "
            
            var streamMap = ""
            for (i, res) in selectedResolutions.enumerated() {
                filterComplex += "[v\(i)]scale=\(res.scale)[vout\(i)]"
                if i < selectedResolutions.count - 1 { filterComplex += "; " }
                
                args.append(contentsOf: [
                    "-map", "[vout\(i)]",
                    "-map", "a:0",
                    "-c:v:\(i)", "libx264",
                    "-b:v:\(i)", res.bitrate,
                    "-c:a:\(i)", "aac",
                    "-b:a:\(i)", "128k",
                    "-preset", "veryfast"
                ])
                streamMap += "v:\(i),a:\(i) "
            }
            
            args.append(contentsOf: [
                "-filter_complex", filterComplex,
                "-f", "hls",
                "-hls_time", "\(state.liveSegmentLength)",
                "-hls_list_size", "\(state.livePlaylistSize)",
                "-hls_flags", hlsFlags,
                "-hls_segment_type", "mpegts",
                "-master_pl_name", "master.m3u8",
                "-var_stream_map", streamMap.trimmingCharacters(in: .whitespaces),
                "-hls_segment_filename", hlsDir.appendingPathComponent("stream_%v_segment_%05d.ts").path,
                hlsDir.appendingPathComponent("stream_%v.m3u8").path
            ])
        }
        
        process.arguments = args
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError  = pipe
        
        let fileHandle = pipe.fileHandleForReading
        fileHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let self else { return }
            if let line = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async {
                    self.parseFFmpegOutput(line)
                }
            }
        }
        
        process.terminationHandler = { [weak self] _ in
            fileHandle.readabilityHandler = nil
            DispatchQueue.main.async {
                self?.isRunning = false
                self?.clientConnected = false
                self?.activeStreams = 0
                self?.activeHLSOutputs = 0
                self?.totalBitrate = "0 Mbps"
                self?.appendLog(level: "INFO", thread: "FFmpeg", message: "RTMP Server stopped")
                self?.s3UploaderTask?.cancel()
            }
        }
        
        do {
            try process.run()
            ffmpegProcess = process
            ffmpegPipe = pipe
            isRunning = true
            clientConnected = false
            appendLog(level: "INFO", thread: "Main", message: "RTMP Server listening on \(listenUrl)")
            appendLog(level: "INFO", thread: "Main", message: "HLS output directory: \(hlsDir.path)")
            appendLog(level: "INFO", thread: "Main", message: "Waiting for OBS connection...")
            
            // Start background S3 uploader if configured
            if state.enableS3Upload, let profile = state.activeProfile {
                let keys = state.getActiveS3Keys()
                let uploader = S3Uploader(
                    endpoint: profile.endpoint,
                    bucket: profile.bucket,
                    accessKey: keys.keyId,
                    secretKey: keys.appKey,
                    cdnUrl: profile.cdnUrl,
                    targetFolder: "", // Intentionally empty: user dictates path via Live Tab
                    cdnPathToStrip: profile.cdnPathToStrip
                )
                
                let liveFolder = state.liveS3Folder.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                let basePath = liveFolder.isEmpty ? listenKey : "\(liveFolder)/\(listenKey)"
                
                appendLog(level: "INFO", thread: "S3", message: "S3 upload enabled → s3://\(profile.bucket)/\(basePath)/")
                startBackgroundUploader(dir: hlsDir, uploader: uploader, basePath: basePath, bufferSegments: state.liveBufferSegments)
            }
        } catch {
            appendLog(level: "ERROR", thread: "Main", message: "Failed to start FFmpeg: \(error.localizedDescription)")
        }
    }
    
    func stopServer() {
        ffmpegPipe?.fileHandleForReading.readabilityHandler = nil
        ffmpegProcess?.terminate()
        ffmpegProcess = nil
        ffmpegPipe = nil
        s3UploaderTask?.cancel()
        isRunning = false
        clientConnected = false
        activeStreams = 0
        activeHLSOutputs = 0
        totalBitrate = "0 Mbps"
    }
    
    private func appendLog(level: String, thread: String, message: String) {
        let entry = LogEntry(timestamp: Date(), level: level, thread: thread, message: message.trimmingCharacters(in: .newlines))
        logs.insert(entry, at: 0) // Newest first
        if logs.count > 1000 {
            logs.removeLast(logs.count - 1000)
        }
    }
    
    private func parseFFmpegOutput(_ output: String) {
        let lines = output.components(separatedBy: "\n")
        for line in lines where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            // Detect OBS/encoder connection
            if line.contains("Handshaking") || line.contains("Connected") || line.contains("Input #0") || line.contains("Stream #0") && line.contains("Video") {
                if !clientConnected {
                    clientConnected = true
                    activeStreams = 1
                    activeHLSOutputs = 1
                    appendLog(level: "INFO", thread: "RTMP", message: "✅ Encoder connected!")
                }
            }
            
            // Parse bitrate
            if line.contains("bitrate=") {
                if let range = line.range(of: "bitrate=\\s*[0-9.]+\\s*[kM]bits/s", options: .regularExpression) {
                    let match = String(line[range]).replacingOccurrences(of: "bitrate=", with: "").trimmingCharacters(in: .whitespaces)
                    totalBitrate = match.replacingOccurrences(of: "kbits/s", with: "Kbps").replacingOccurrences(of: "Mbits/s", with: "Mbps")
                }
            }
            
            // Log everything for debugging, but skip overly verbose progress lines
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let isProgressLine = trimmed.hasPrefix("frame=") || trimmed.hasPrefix("size=") || trimmed.hasPrefix("Press")
            if !isProgressLine {
                let level: String
                if line.lowercased().contains("error") { level = "ERROR" }
                else if line.lowercased().contains("warning") { level = "WARN" }
                else { level = "INFO" }
                appendLog(level: level, thread: "FFmpeg", message: trimmed)
            }
        }
    }
    
    /// Upload segments to S3 in the correct order.
    /// - bufferSegments: How many .ts segments must exist before we start uploading .m3u8 playlists.
    ///   This prevents the player from seeing a playlist entry before the segment file is live.
    private func startBackgroundUploader(dir: URL, uploader: S3Uploader, basePath: String, bufferSegments: Int = 3) {
        s3UploaderTask = Task {
            var uploadedTsFiles = Set<String>()
            var m3u8UploadedAt = [String: Date]()   // track last upload time per m3u8
            let fm = FileManager.default
            
            await MainActor.run {
                appendLog(level: "INFO", thread: "S3", message: "Background uploader started (buffer: \(bufferSegments) segments)...")
            }
            
            while !Task.isCancelled {
                do {
                    let allFiles = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
                    
                    // Only process fully written .ts files (not .tmp)
                    let tsFiles  = allFiles.filter { $0.hasSuffix(".ts") }.sorted()
                    let m3u8Files = allFiles.filter { $0.hasSuffix(".m3u8") }.sorted()
                    
                    // Step 1 — upload any new .ts segments
                    for file in tsFiles {
                        guard !uploadedTsFiles.contains(file) else { continue }
                        if Task.isCancelled { break }
                        let fileURL = dir.appendingPathComponent(file)
                        let s3Key   = basePath.isEmpty ? file : "\(basePath)/\(file)"
                        do {
                            try await uploader.client.putObject(path: s3Key, fileURL: fileURL, contentType: "video/MP2T")
                            uploadedTsFiles.insert(file)
                            await MainActor.run {
                                self.appendLog(level: "INFO", thread: "S3", message: "↑ \(file) → \(s3Key)")
                            }
                        } catch {
                            await MainActor.run {
                                self.appendLog(level: "WARN", thread: "S3", message: "Upload failed \(file): \(error.localizedDescription)")
                            }
                        }
                    }
                    
                    // Step 2 — upload .m3u8 playlists only after buffer has been satisfied
                    // i.e. once we have uploaded at least `bufferSegments` .ts files
                    let tsUploaded = uploadedTsFiles.count
                    if tsUploaded >= bufferSegments {
                        for file in m3u8Files {
                            if Task.isCancelled { break }
                            let fileURL = dir.appendingPathComponent(file)
                            let s3Key   = basePath.isEmpty ? file : "\(basePath)/\(file)"
                            
                            // Throttle m3u8 uploads: upload at most once per segment length cycle
                            // but always upload if the file has changed recently
                            let lastUpload = m3u8UploadedAt[file] ?? .distantPast
                            let timeSinceLastUpload = Date().timeIntervalSince(lastUpload)
                            guard timeSinceLastUpload >= 1.5 else { continue } // upload at most every 1.5s
                            
                            do {
                                try await uploader.client.putObject(path: s3Key, fileURL: fileURL, contentType: "application/vnd.apple.mpegurl")
                                m3u8UploadedAt[file] = Date()
                                await MainActor.run {
                                    self.appendLog(level: "INFO", thread: "S3", message: "↑ \(file) → \(s3Key)")
                                }
                            } catch {
                                await MainActor.run {
                                    self.appendLog(level: "WARN", thread: "S3", message: "Playlist upload failed \(file): \(error.localizedDescription)")
                                }
                            }
                        }
                    }
                }
                
                try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5s poll
            }
            
            await MainActor.run {
                appendLog(level: "INFO", thread: "S3", message: "Background uploader stopped.")
            }
        }
    }
    
    func pregeneratePlaylists(state: ProcessorState, streamKey: String) async {
        guard state.enableS3Upload, let profile = state.activeProfile else { return }
        
        let keys = state.getActiveS3Keys()
        let uploader = S3Uploader(
            endpoint: profile.endpoint,
            bucket: profile.bucket,
            accessKey: keys.keyId,
            secretKey: keys.appKey,
            cdnUrl: profile.cdnUrl,
            targetFolder: "",
            cdnPathToStrip: profile.cdnPathToStrip
        )
        
        let liveFolder = state.liveS3Folder.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let basePath = liveFolder.isEmpty ? streamKey : "\(liveFolder)/\(streamKey)"
        
        struct Resolution { let name: String; let bitrate: String; let res: String }
        var selectedResolutions: [Resolution] = []
        if state.enable1080p { selectedResolutions.append(Resolution(name: "1080p", bitrate: "5000000", res: "1920x1080")) }
        if state.enable720p  { selectedResolutions.append(Resolution(name: "720p",  bitrate: "2800000", res: "1280x720"))  }
        if state.enable480p  { selectedResolutions.append(Resolution(name: "480p",  bitrate: "1400000", res: "854x480"))   }
        if state.enable240p  { selectedResolutions.append(Resolution(name: "240p",  bitrate: "400000",  res: "426x240"))   }
        
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        var masterContent = "#EXTM3U\n#EXT-X-VERSION:3\n"
        var uploads: [(URL, String)] = []
        
        if selectedResolutions.isEmpty {
            masterContent += "#EXT-X-TARGETDURATION:\(state.liveSegmentLength)\n#EXT-X-MEDIA-SEQUENCE:0\n"
        } else {
            for (i, res) in selectedResolutions.enumerated() {
                masterContent += "#EXT-X-STREAM-INF:BANDWIDTH=\(res.bitrate),RESOLUTION=\(res.res)\nstream_\(i).m3u8\n"
                let variantContent = "#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-TARGETDURATION:\(state.liveSegmentLength)\n#EXT-X-MEDIA-SEQUENCE:0\n"
                let variantURL = tempDir.appendingPathComponent("stream_\(i).m3u8")
                try? variantContent.write(to: variantURL, atomically: true, encoding: .utf8)
                uploads.append((variantURL, "\(basePath)/stream_\(i).m3u8"))
            }
        }
        
        let masterURL = tempDir.appendingPathComponent("master.m3u8")
        try? masterContent.write(to: masterURL, atomically: true, encoding: .utf8)
        uploads.append((masterURL, "\(basePath)/master.m3u8"))
        
        for (url, s3Key) in uploads {
            do {
                try await uploader.client.putObject(path: s3Key, fileURL: url, contentType: "application/vnd.apple.mpegurl")
                appendLog(level: "INFO", thread: "S3", message: "Pre-generated playlist uploaded: \(s3Key)")
            } catch {
                appendLog(level: "WARN", thread: "S3", message: "Failed to pre-generate playlist \(s3Key): \(error.localizedDescription)")
            }
        }
    }
}
