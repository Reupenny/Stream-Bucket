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
    /// Number of active push/record destinations for the current stream.
    @Published var activeDestinations: Int = 0
    /// Count of HLS segments uploaded to destinations this session.
    @Published var uploadedSegments: Int = 0
    
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

        // Resolve per-stream settings/destinations (fall back to global defaults
        // when no stream is selected, e.g. the generic "stream" fallback).
        let stream = state.scheduledStreams.first { $0.id == state.selectedStreamId }
        let settings = stream?.settings ?? StreamSettings(
            enable1080p: state.enable1080p,
            enable720p: state.enable720p,
            enable480p: state.enable480p,
            enable240p: state.enable240p,
            segmentLength: state.liveSegmentLength,
            playlistSize: state.livePlaylistSize,
            bufferSegments: state.liveBufferSegments,
            recordToS3: state.enableS3Upload
        )
        // When no stream is selected (Dashboard "Start Server"), fall back to the
        // global defaults: S3 if enabled, plus YouTube if a default key is set.
        let destinations: [StreamDestination]
        if let stream {
            destinations = stream.destinations
        } else {
            var fallback: [StreamDestination] = []
            if state.enableS3Upload {
                fallback.append(StreamDestination(type: .s3, profileId: state.selectedProfileId, s3Folder: state.liveS3Folder))
            }
            let d = state.liveDefaults
            if !d.youtubeStreamKey.isEmpty {
                fallback.append(StreamDestination(type: .youtube, rtmpUrl: d.youtubeRtmpUrl, streamKey: d.youtubeStreamKey))
            }
            destinations = fallback
        }

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
        if settings.enable1080p { selectedResolutions.append(Resolution(name: "1080p", scale: "1920:1080", bitrate: "5000k")) }
        if settings.enable720p  { selectedResolutions.append(Resolution(name: "720p",  scale: "1280:720",  bitrate: "2800k")) }
        if settings.enable480p  { selectedResolutions.append(Resolution(name: "480p",  scale: "854:480",   bitrate: "1400k")) }
        if settings.enable240p  { selectedResolutions.append(Resolution(name: "240p",  scale: "426:240",   bitrate: "400k"))  }
        
        // playlistSize == 0 means "keep all segments" (event-style / VOD replayable)
        let hlsFlags = settings.playlistSize == 0
            ? "append_list+independent_segments"
            : "delete_segments+append_list+independent_segments"
        
        if selectedResolutions.isEmpty {
            // Direct copy (no ABR)
            args.append(contentsOf: [
                "-c:v", "copy",
                "-c:a", "aac",
                "-b:a", "128k",
                "-f", "hls",
                "-hls_time", "\(settings.segmentLength)",
                "-hls_list_size", "\(settings.playlistSize)",
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
                "-hls_time", "\(settings.segmentLength)",
                "-hls_list_size", "\(settings.playlistSize)",
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
                self?.activeDestinations = 0
                self?.uploadedSegments = 0
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
            appendLog(level: "INFO", thread: "Main", message: "Waiting for connection...")
            appendLog(level: "INFO", thread: "Main", message: "Configured destinations: \(destinations.map { $0.type.rawValue }.joined(separator: ", "))")
            activeDestinations = destinations.count
            
            // Start a background uploader / push for each configured destination.
            for dest in destinations {
                switch dest.type {
                case .s3:
                    guard let profileId = dest.profileId,
                          let profile = state.s3Profiles.first(where: { $0.id == profileId }) else { continue }
                    let keys = state.getActiveS3Keys()
                    let uploader = S3Uploader(
                        endpoint: profile.endpoint,
                        bucket: profile.bucket,
                        accessKey: keys.keyId,
                        secretKey: keys.appKey,
                        cdnUrl: profile.cdnUrl,
                        targetFolder: "", // path dictated by the destination's s3Folder
                        cdnPathToStrip: profile.cdnPathToStrip
                    )
                    let liveFolder = dest.s3Folder.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    let basePath = liveFolder.isEmpty ? listenKey : "\(liveFolder)/\(listenKey)"
                    appendLog(level: "INFO", thread: "S3", message: "S3 upload enabled → s3://\(profile.bucket)/\(basePath)/")
                    s3UploaderTask = uploader.startWatching(dir: hlsDir, basePath: basePath, bufferSegments: settings.bufferSegments, sourceComplete: { false }) { msg in
                        Task { @MainActor in
                            if msg.contains(".ts") { self.uploadedSegments += 1 }
                            self.appendLog(level: "INFO", thread: "S3", message: msg)
                        }
                    }
                case .youtube:
                    // Push the local HLS to YouTube's RTMP ingest. YouTube expects
                    // a single RTMP stream, so we re-mux the master playlist to RTMP.
                    let ytUrl = (dest.rtmpUrl.isEmpty ? "rtmp://a.rtmp.youtube.com/live2" : dest.rtmpUrl)
                    let ytKey = dest.streamKey
                    guard !ytKey.isEmpty else {
                        appendLog(level: "WARN", thread: "YouTube", message: "Skipping YouTube: no stream key configured.")
                        continue
                    }
                    appendLog(level: "INFO", thread: "YouTube", message: "YouTube RTMP push enabled → \(ytUrl)/\(ytKey)")
                    // Re-mux a concrete variant playlist (not the ABR master) so
                    // ffmpeg pushes a single deterministic rendition to YouTube.
                    let ytPlaylist = selectedResolutions.isEmpty ? "master.m3u8" : "stream_0.m3u8"
                    startYouTubePush(hlsDir: hlsDir, masterName: ytPlaylist, rtmpUrl: ytUrl, streamKey: ytKey)
                }
            }
        } catch {
            appendLog(level: "ERROR", thread: "Main", message: "Failed to start FFmpeg: \(error.localizedDescription)")
        }
    }
    
    func stopServer() {
        ffmpegPipe?.fileHandleForReading.readabilityHandler = nil
        ffmpegProcess?.terminate()
        ffmpegProcess = nil
        youtubePushTask?.cancel()
        youtubePushTask = nil
        ffmpegPipe = nil
        s3UploaderTask?.cancel()
        isRunning = false
        clientConnected = false
        activeDestinations = 0
        uploadedSegments = 0
        activeStreams = 0
        activeHLSOutputs = 0
        totalBitrate = "0 Mbps"
    }

    /// Pushes the generated HLS master playlist to a YouTube RTMP ingest URL.
    /// YouTube requires a single RTMP stream, so we re-mux the ABR master to one
    /// RTMP output. Runs as a detached background task; cancelled on stopServer.
    private var youtubePushTask: Task<Void, Never>?
    private func startYouTubePush(hlsDir: URL, masterName: String, rtmpUrl: String, streamKey: String) {
        let masterURL = hlsDir.appendingPathComponent(masterName)
        youtubePushTask = Task.detached(priority: .utility) {
            // The master playlist is only written once the encoder connects and
            // ffmpeg begins producing segments. Wait (with a timeout) for it.
            var waited: TimeInterval = 0
            let pollInterval: TimeInterval = 0.5
            let maxWait: TimeInterval = 60
            while !FileManager.default.fileExists(atPath: masterURL.path) {
                if Task.isCancelled { return }
                try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
                waited += pollInterval
                if waited >= maxWait {
                    await MainActor.run { self.appendLog(level: "WARN", thread: "YouTube", message: "Timed out waiting for \(masterName) to appear.") }
                    return
                }
            }
            guard let ffmpeg = FFmpegWrapper.shared.findFFmpeg() else {
                await MainActor.run { self.appendLog(level: "ERROR", thread: "YouTube", message: "ffmpeg not found for YouTube push.") }
                return
            }
            let process = Process()
            process.executableURL = ffmpeg
            process.arguments = [
                "-re",
                "-fflags", "+genpts",
                "-flags", "+global_header",
                "-i", masterURL.path,
                "-c", "copy",
                "-f", "flv",
                "\(rtmpUrl)/\(streamKey)"
            ]
            await MainActor.run { self.appendLog(level: "INFO", thread: "YouTube", message: "Push command: \(ffmpeg.lastPathComponent) \(process.arguments!.joined(separator: " "))") }
            let pipe = Pipe()
            process.standardError = pipe
            let handle = pipe.fileHandleForReading
            handle.readabilityHandler = { fh in
                let data = fh.availableData
                guard !data.isEmpty else { return }
                if let line = String(data: data, encoding: .utf8) {
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        Task { @MainActor in
                            self.appendLog(level: "INFO", thread: "YouTube", message: trimmed)
                        }
                    }
                }
            }
            do {
                try process.run()
                process.waitUntilExit()
                let code = process.terminationStatus
                await MainActor.run {
                    if code == 0 {
                        self.appendLog(level: "INFO", thread: "YouTube", message: "Push process exited cleanly.")
                    } else {
                        self.appendLog(level: "WARN", thread: "YouTube", message: "Push process exited with code \(code).")
                    }
                }
            } catch {
                await MainActor.run { self.appendLog(level: "ERROR", thread: "YouTube", message: "YouTube push failed: \(error.localizedDescription)") }
            }
        }
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
    
    func pregeneratePlaylists(state: ProcessorState, stream: ScheduledStream) async {
        let s3Dest = stream.destinations.first { $0.type == .s3 }
        guard let dest = s3Dest,
              let profileId = dest.profileId,
              let profile = state.s3Profiles.first(where: { $0.id == profileId }) else { return }
        
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
        
        let liveFolder = dest.s3Folder.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let basePath = liveFolder.isEmpty ? stream.streamKey : "\(liveFolder)/\(stream.streamKey)"
        
        struct Resolution { let name: String; let bitrate: String; let res: String }
        var selectedResolutions: [Resolution] = []
        if stream.settings.enable1080p { selectedResolutions.append(Resolution(name: "1080p", bitrate: "5000000", res: "1920x1080")) }
        if stream.settings.enable720p  { selectedResolutions.append(Resolution(name: "720p",  bitrate: "2800000", res: "1280x720"))  }
        if stream.settings.enable480p  { selectedResolutions.append(Resolution(name: "480p",  bitrate: "1400000", res: "854x480"))   }
        if stream.settings.enable240p  { selectedResolutions.append(Resolution(name: "240p",  bitrate: "400000",  res: "426x240"))   }
        
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        var masterContent = "#EXTM3U\n#EXT-X-VERSION:3\n"
        var uploads: [(URL, String)] = []
        
        if selectedResolutions.isEmpty {
            masterContent += "#EXT-X-TARGETDURATION:\(stream.settings.segmentLength)\n#EXT-X-MEDIA-SEQUENCE:0\n"
        } else {
            for (i, res) in selectedResolutions.enumerated() {
                masterContent += "#EXT-X-STREAM-INF:BANDWIDTH=\(res.bitrate),RESOLUTION=\(res.res)\nstream_\(i).m3u8\n"
                let variantContent = "#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-TARGETDURATION:\(stream.settings.segmentLength)\n#EXT-X-MEDIA-SEQUENCE:0\n"
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
