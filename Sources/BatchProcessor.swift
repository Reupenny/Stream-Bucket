import Foundation

/// Minimal reference-type box so a `sourceComplete` closure can observe a value
/// mutated elsewhere (closures capture value types by value, not by reference).
private final class Box<T> {
    var value: T
    init(_ value: T) { self.value = value }
}

class BatchProcessor {
    let state: ProcessorState
    
    init(state: ProcessorState) {
        self.state = state
    }
    
    struct Config {
        let enable1080p: Bool
        let enable720p: Bool
        let enable480p: Bool
        let enable240p: Bool
        let segmentLength: Int
        let audioBitrate: String
        let generateThumbnails: Bool
        let generatePoster: Bool
        let generateSpriteSheets: Bool
        let generateVTT: Bool
        let enableS3Upload: Bool
        let simultaneousMode: Bool
        let s3Endpoint: String
        let s3Bucket: String
        let s3KeyId: String
        let s3AppKey: String
        let s3CdnUrl: String
        let targetFolder: String
        let customS3Path: String
        let overwriteExisting: Bool
        let cdnPathToStrip: String
    }
    
    func process(outputFolder: URL) async {
        guard FFmpegWrapper.shared.checkFFmpeg() else {
            await MainActor.run {
                state.appendLog("ERROR: ffmpeg or ffprobe not found in system path. Please install it (e.g. via Homebrew).")
            }
            return
        }
        
        let config = await MainActor.run {
            let keys = state.getActiveS3Keys()
            return Config(
                enable1080p: state.enable1080p,
                enable720p: state.enable720p,
                enable480p: state.enable480p,
                enable240p: state.enable240p,
                segmentLength: state.segmentLength,
                audioBitrate: state.audioBitrate,
                generateThumbnails: state.generateThumbnails,
                generatePoster: state.generatePoster,
                generateSpriteSheets: state.generateSpriteSheets,
                generateVTT: state.generateVTT,
                enableS3Upload: state.enableS3Upload,
                simultaneousMode: state.simultaneousMode,
                s3Endpoint: state.activeProfile?.endpoint ?? "",
                s3Bucket: state.activeProfile?.bucket ?? "",
                s3KeyId: keys.keyId,
                s3AppKey: keys.appKey,
                s3CdnUrl: state.activeProfile?.cdnUrl ?? "",
                targetFolder: state.activeProfile?.targetFolder ?? "",
                customS3Path: state.customS3Path,
                overwriteExisting: state.overwriteExisting,
                cdnPathToStrip: state.activeProfile?.cdnPathToStrip ?? ""
            )
        }
        
        let fileManager = FileManager.default
        
        let itemsToProcess = await MainActor.run { state.queue.filter { $0.isEnabled } }
        if itemsToProcess.isEmpty {
            await MainActor.run { state.appendLog("No enabled files in the queue to process.") }
            return
        }
        
        let totalFiles = itemsToProcess.count
        
        for (index, item) in itemsToProcess.enumerated() {
            let safeFilename = item.filename.replacingOccurrences(of: " ", with: "_")
            let filename = safeFilename
            
            await MainActor.run {
                state.currentFile = filename
                state.progress = Double(index) / Double(totalFiles)
                state.uploadProgress = 0.0
                state.updateQueueStatus(id: item.id, status: "Processing")
                state.appendLog("--- Processing: \(filename) ---")
            }
            
            let fileOutputFolder = outputFolder.appendingPathComponent(filename)
            do {
                if !fileManager.fileExists(atPath: fileOutputFolder.path) {
                    try fileManager.createDirectory(at: fileOutputFolder, withIntermediateDirectories: true)
                }
                let uploadUrl = try await processSingleFile(input: item.url, outputDir: fileOutputFolder, config: config, filename: filename, fileIndex: index, totalFiles: totalFiles, itemId: item.id)
                
                await MainActor.run {
                    state.updateQueueStatus(id: item.id, status: "Done", uploadUrl: uploadUrl)
                }
            } catch {
                await MainActor.run {
                    state.updateQueueStatus(id: item.id, status: "Failed")
                    state.appendLog("ERROR processing \(filename): \(error.localizedDescription)")
                }
            }
        }
        
        await MainActor.run {
            state.progress = 1.0
            state.uploadProgress = 1.0
            state.currentFile = ""
            state.appendLog("--- Batch Processing Complete ---")
        }
    }
    
    private func processSingleFile(input: URL, outputDir: URL, config: Config, filename: String, fileIndex: Int, totalFiles: Int, itemId: UUID) async throws -> String? {
        // 1. Get duration
        let duration = try await FFmpegWrapper.shared.getDuration(input: input)
        
        let enabledStreams: [(res: String, bandwidth: Int)] = [
            config.enable1080p ? ("1080p", 5000000) : nil,
            config.enable720p  ? ("720p",  2800000) : nil,
            config.enable480p  ? ("480p",  1400000) : nil,
            config.enable240p  ? ("240p",  400000)  : nil,
        ].compactMap { $0 }

        // Steps: poster + spritesheet + vtt + streams
        var totalSteps = enabledStreams.count
        if config.generatePoster && config.generateThumbnails { totalSteps += 1 }
        if config.generateSpriteSheets { totalSteps += 1 }
        if config.generateVTT { totalSteps += 1 }
        var completedSteps = 0

        let updateProgress = { @MainActor [self] in
            let perFileFraction = 1.0 / Double(max(totalFiles, 1))
            let fileBase = perFileFraction * Double(fileIndex)
            let stepFraction = perFileFraction * (Double(completedSteps) / Double(max(totalSteps, 1)))
            self.state.progress = min(fileBase + stepFraction, 1.0)
        }
        
        let cols = 5; let rows = 5; let interval = 10.0

        // Shared S3 upload pipeline — identical to the live-streaming watcher.
        // A directory watcher uploads segments/assets as they are written and
        // playlists once the segment buffer is satisfied, so a player never sees
        // a playlist referencing a segment that isn't live yet.
        // Build the S3 key prefix: "<targetFolder>/<customPath>/<filename>".
        // Trim slashes from both ends of each component and join with a single "/"
        // so we can never produce doubled folders like "videos//videos" even if a
        // profile value or the filename carries stray slashes.
        let trimmedFolder = config.targetFolder.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let trimmedCustom = config.customS3Path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let trimmedName   = filename.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let basePath = [trimmedFolder, trimmedCustom, trimmedName].filter { !$0.isEmpty }.joined(separator: "/")

        // If uploading and overwrite is not enabled, check whether the destination
        // already exists. If it does, ask the user whether to overwrite or skip.
        if config.enableS3Upload, !config.overwriteExisting {
            let exists = await self.destinationExists(basePath: basePath, config: config)
            if exists {
                let proceed = await self.confirmOverwrite(destination: basePath, filename: filename)
                if !proceed {
                    await MainActor.run {
                        state.updateQueueStatus(id: itemId, status: "Skipped")
                        state.appendLog("Skipped (destination exists): \(basePath)")
                    }
                    return nil
                }
            }
        }

        var uploaderTask: Task<Void, Never>?
        // Box so the watcher's `sourceComplete` closure can observe completion
        // after encoding finishes (set below), letting it drain remaining
        // playlists/assets and exit cleanly instead of being cancelled mid-upload.
        let encodingFinished = Box(false)
        if config.enableS3Upload {
            let uploader = S3Uploader(endpoint: config.s3Endpoint, bucket: config.s3Bucket, accessKey: config.s3KeyId, secretKey: config.s3AppKey, cdnUrl: config.s3CdnUrl, targetFolder: config.targetFolder, cdnPathToStrip: config.cdnPathToStrip)
            await MainActor.run { state.appendLog("Starting S3 upload watcher for \(filename)…") }
            uploaderTask = uploader.startWatching(dir: outputDir, basePath: basePath, bufferSegments: 3, sourceComplete: { encodingFinished.value }) { msg in
                Task { @MainActor in self.state.appendLog("[S3] \(msg)") }
            }
        }

        if config.simultaneousMode {
            // --- SIMULTANEOUS MODE: Run thumbnail tasks in parallel with encoding ---
            await MainActor.run { state.appendLog("[Simultaneous] Starting parallel encode + upload...") }

            // Run thumbnail generation concurrently with encoding
            async let posterTask: Void = {
                if config.generatePoster && config.generateThumbnails {
                    let posterURL = outputDir.appendingPathComponent("poster.jpg")
                    try? await FFmpegWrapper.shared.extractPoster(input: input, output: posterURL, onLog: { _ in })
                }
            }()

            async let spriteTask: Void = {
                if config.generateSpriteSheets {
                    try? await FFmpegWrapper.shared.extractSpriteSheet(input: input, outputDir: outputDir, interval: interval, cols: cols, rows: rows, onLog: { _ in })
                }
            }()

            // HLS encoding (sequential per resolution)
            var masterPlaylistContent = "#EXTM3U\n#EXT-X-VERSION:3\n"
            for stream in enabledStreams {
                await MainActor.run { state.appendLog("[Simultaneous] Encoding \(stream.res)...") }
                try await generateHLS(input: input, outputDir: outputDir, resolution: stream.res, config: config)
                completedSteps += 1
                await updateProgress()
                let resString = resolutionToScale(stream.res)
                masterPlaylistContent += "#EXT-X-STREAM-INF:BANDWIDTH=\(stream.bandwidth),RESOLUTION=\(resString)\n"
                masterPlaylistContent += "\(stream.res).m3u8\n"
            }

            // Wait for parallel thumbnail tasks to complete
            _ = await (posterTask, spriteTask)

            if config.generateVTT {
                let vttURL = outputDir.appendingPathComponent("thumbnails.vtt")
                try SpriteSheetGenerator.generateVTT(duration: duration, interval: interval, cols: cols, rows: rows, outputURL: vttURL)
            }

            // Write master.m3u8 then let the uploader push it
            let masterURL = outputDir.appendingPathComponent("master.m3u8")
            try masterPlaylistContent.write(to: masterURL, atomically: true, encoding: .utf8)
            await MainActor.run { state.appendLog("[Simultaneous] Complete: \(filename)") }

        } else {
            // --- SEQUENTIAL MODE (default) ---

            // 2. Extract poster
            if config.generatePoster && config.generateThumbnails {
                let posterURL = outputDir.appendingPathComponent("poster.jpg")
                await MainActor.run { state.appendLog("Extracting poster...") }
                try await FFmpegWrapper.shared.extractPoster(input: input, output: posterURL, onLog: { _ in })
                completedSteps += 1
                await updateProgress()
            }

            // 3. Extract sprite sheet
            if config.generateSpriteSheets {
                await MainActor.run { state.appendLog("Extracting sprite sheets...") }
                try await FFmpegWrapper.shared.extractSpriteSheet(input: input, outputDir: outputDir, interval: interval, cols: cols, rows: rows, onLog: { _ in })
                completedSteps += 1
                await updateProgress()
            }

            // 4. Generate VTT
            if config.generateVTT {
                let vttURL = outputDir.appendingPathComponent("thumbnails.vtt")
                try SpriteSheetGenerator.generateVTT(duration: duration, interval: interval, cols: cols, rows: rows, outputURL: vttURL)
                completedSteps += 1
                await updateProgress()
            }

            // 5. Generate HLS for each resolution
            var masterPlaylistContent = "#EXTM3U\n#EXT-X-VERSION:3\n"

            for stream in enabledStreams {
                await MainActor.run { state.appendLog("Encoding \(stream.res)...") }
                try await generateHLS(input: input, outputDir: outputDir, resolution: stream.res, config: config)
                completedSteps += 1
                await updateProgress()

                let resString = resolutionToScale(stream.res)
                masterPlaylistContent += "#EXT-X-STREAM-INF:BANDWIDTH=\(stream.bandwidth),RESOLUTION=\(resString)\n"
                masterPlaylistContent += "\(stream.res).m3u8\n"
            }

            // 6. Write master playlist
            let masterURL = outputDir.appendingPathComponent("master.m3u8")
            try masterPlaylistContent.write(to: masterURL, atomically: true, encoding: .utf8)
            await MainActor.run { state.appendLog("Encoding completed for \(filename)") }
        }

        // Signal the watcher that the source is done so it drains remaining
        // playlists/assets (e.g. master.m3u8, thumbnails.vtt) and exits cleanly.
        if config.enableS3Upload {
            encodingFinished.value = true
            // Wait for the watcher to finish uploading everything (no cancellation,
            // so in-flight uploads like thumbnails.vtt aren't killed mid-flight).
            await uploaderTask?.value
            await MainActor.run {
                state.uploadProgress = 1.0
                state.appendLog("S3 upload complete for \(filename)")
            }
        }

        // Return CDN URL for master playlist
        let masterPath = basePath + "/master.m3u8"
        if config.enableS3Upload {
            if !config.s3CdnUrl.isEmpty {
                let base = config.s3CdnUrl.hasSuffix("/") ? String(config.s3CdnUrl.dropLast()) : config.s3CdnUrl
                var key = masterPath
                if !config.cdnPathToStrip.isEmpty, key.hasPrefix(config.cdnPathToStrip) {
                    key = String(key.dropFirst(config.cdnPathToStrip.count))
                    if key.hasPrefix("/") { key = String(key.dropFirst()) }
                }
                return "\(base)/\(key)"
            }
            return "https://\(config.s3Endpoint)/\(config.s3Bucket)/\(masterPath)"
        }
        return nil
    }

    // MARK: - Overwrite handling

    /// Checks whether the destination folder already has a `master.m3u8`, which is
    /// the last file written — its presence means a prior upload of this file exists.
    private func destinationExists(basePath: String, config: Config) async -> Bool {
        let keys = await MainActor.run { state.getActiveS3Keys() }
        let client = S3Client(endpoint: config.s3Endpoint, bucket: config.s3Bucket, accessKey: keys.keyId, secretKey: keys.appKey)
        do {
            return try await client.objectExists(path: basePath + "/master.m3u8")
        } catch {
            // If we can't verify, err on the side of proceeding (don't block the user).
            await MainActor.run { state.appendLog("Could not check destination existence: \(error.localizedDescription)") }
            return false
        }
    }

    /// Presents the overwrite confirmation alert and suspends until the user
    /// chooses. Returns `true` to overwrite, `false` to skip the file.
    private func confirmOverwrite(destination: String, filename: String) async -> Bool {
        await withCheckedContinuation { continuation in
            Task { @MainActor in
                // If a prompt is somehow already pending, resolve it as skip to avoid a deadlock.
                if state.overwriteContinuation != nil {
                    continuation.resume(returning: false)
                    return
                }
                state.overwriteContinuation = continuation
                state.overwritePrompt = ProcessorState.OverwritePrompt(destination: destination, filename: filename)
            }
        }
    }
    
    private func generateHLS(input: URL, outputDir: URL, resolution: String, config: Config) async throws {
        let playlist = outputDir.appendingPathComponent("\(resolution).m3u8")
        let segments = outputDir.appendingPathComponent("\(resolution)_%03d.ts")
        
        let scale = resolutionToScale(resolution)
        
        let args = [
            "-y",
            "-i", input.path,
            "-vf", "scale=\(scale)",
            "-c:v", "libx264",
            "-c:a", "aac",
            "-b:a", config.audioBitrate,
            "-f", "hls",
            "-hls_time", "\(config.segmentLength)",
            "-hls_playlist_type", "vod",
            "-hls_segment_filename", segments.path,
            playlist.path
        ]
        
        try await FFmpegWrapper.shared.run(arguments: args, onLog: { msg in
            // Filter logs
        })
    }
    
    private func resolutionToScale(_ res: String) -> String {
        switch res {
        case "1080p": return "1920x1080"
        case "720p": return "1280x720"
        case "480p": return "854x480"
        case "240p": return "426x240"
        default: return "1920x1080"
        }
    }
}
