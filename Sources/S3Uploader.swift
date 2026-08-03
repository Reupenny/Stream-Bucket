import Foundation

class S3Uploader {
    let client: S3Client
    let cdnUrl: String
    let targetFolder: String
    let cdnPathToStrip: String
    
    init(endpoint: String, bucket: String, accessKey: String, secretKey: String, cdnUrl: String, targetFolder: String = "", cdnPathToStrip: String = "") {
        self.client = S3Client(endpoint: endpoint, bucket: bucket, accessKey: accessKey, secretKey: secretKey)
        self.cdnUrl = cdnUrl
        // Ensure target folder ends with slash if not empty
        self.targetFolder = !targetFolder.isEmpty && !targetFolder.hasSuffix("/") ? targetFolder + "/" : targetFolder
        self.cdnPathToStrip = cdnPathToStrip
    }
    
    func testConnection() async throws {
        try await client.headBucket()
    }
    
    /// Watches `dir` and uploads new files to S3 as they appear, mirroring the
    /// live-streaming upload pipeline.
    ///
    /// - Segments (`.ts`), images (`.jpg`/`.jpeg`/`.png`) and `.vtt` are uploaded
    ///   immediately as they are written.
    /// - `.m3u8` playlists are uploaded only once the segment buffer is satisfied
    ///   (live) **or** once every segment has been uploaded (VOD), so a player
    ///   never sees a playlist referencing a segment that isn't live yet.
    ///
    /// - Parameter sourceComplete: a closure returning `true` once the source has
    ///   finished producing files. When `true`, the watcher performs a final drain
    ///   (uploading any remaining playlists/assets) and exits naturally instead of
    ///   being cancelled mid-upload. For continuous sources (live streaming) pass
    ///   `{ false }` and cancel the returned task to stop.
    ///
    /// Returns a cancellable `Task`. For batch/VOD use, set `sourceComplete` to
    /// `true` when encoding finishes and `await` the task's `value` to ensure every
    /// file (including `master.m3u8`) is uploaded.
    func startWatching(dir: URL, basePath: String, bufferSegments: Int = 3, sourceComplete: @escaping () -> Bool = { false }, onLog: @escaping (String) -> Void) -> Task<Void, Never> {
        // Collapse any accidental "//" and guarantee exactly one trailing slash
        // so keys are always "prefix/file" with no doubled folders.
        let collapsed = basePath.components(separatedBy: "/").filter { !$0.isEmpty }
        let normalizedBase = collapsed.isEmpty ? "" : (collapsed.joined(separator: "/") + "/")

        return Task {
            var uploadedTs = Set<String>()
            var uploadedAssets = Set<String>()
            var m3u8UploadedAt = [String: Date]()
            var drainCount = 0
            let fm = FileManager.default

            while !Task.isCancelled {
                let allFiles = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
                let tsFiles    = allFiles.filter { $0.hasSuffix(".ts") }.sorted()
                let m3u8Files  = allFiles.filter { $0.hasSuffix(".m3u8") }.sorted()
                let assetFiles = allFiles.filter {
                    let l = $0.lowercased()
                    return l.hasSuffix(".jpg") || l.hasSuffix(".jpeg") || l.hasSuffix(".png") || l.hasSuffix(".vtt")
                }.sorted()

                // 1. Upload segments + assets immediately as they appear
                for file in tsFiles + assetFiles {
                    let isTs = file.hasSuffix(".ts")
                    let seen = isTs ? uploadedTs.contains(file) : uploadedAssets.contains(file)
                    guard !seen else { continue }
                    if Task.isCancelled { break }
                    let fileURL = dir.appendingPathComponent(file)
                    let s3Key = normalizedBase + file
                    let ext = fileURL.pathExtension.lowercased()
                    let mime: String
                    switch ext {
                    case "ts":            mime = "video/MP2T"
                    case "jpg", "jpeg":   mime = "image/jpeg"
                    case "png":           mime = "image/png"
                    case "vtt":           mime = "text/vtt"
                    default:              mime = "application/octet-stream"
                    }
                    do {
                        try await client.putObject(path: s3Key, fileURL: fileURL, contentType: mime)
                        if isTs { uploadedTs.insert(file) } else { uploadedAssets.insert(file) }
                        onLog("↑ \(file) → \(s3Key)")
                    } catch {
                        onLog("Upload failed \(file): \(error.localizedDescription)")
                    }
                }

                // 2. Upload playlists once the buffer is satisfied, all segments are
                //    present (VOD), or the source is complete (force a final drain).
                let tsDone   = !tsFiles.isEmpty && uploadedTs.count >= tsFiles.count
                let bufferOk = uploadedTs.count >= max(bufferSegments, 1)
                let force    = sourceComplete()
                if tsDone || bufferOk || force {
                    for file in m3u8Files {
                        if Task.isCancelled { break }
                        let fileURL = dir.appendingPathComponent(file)
                        let s3Key = normalizedBase + file
                        let last = m3u8UploadedAt[file] ?? .distantPast
                        // Skip the throttle only when forcing the final drain.
                        guard force || Date().timeIntervalSince(last) >= 1.5 else { continue }
                        do {
                            try await client.putObject(path: s3Key, fileURL: fileURL, contentType: "application/vnd.apple.mpegurl")
                            m3u8UploadedAt[file] = Date()
                            onLog("↑ \(file) → \(s3Key)")
                        } catch {
                            onLog("Playlist upload failed \(file): \(error.localizedDescription)")
                        }
                    }
                }

                // 3. Exit once the source is done and every file is uploaded.
                //    Bound the drain so a stuck/empty source can't loop forever.
                if force {
                    let allUploaded = uploadedTs.count >= tsFiles.count
                        && uploadedAssets.count >= assetFiles.count
                        && m3u8UploadedAt.count >= m3u8Files.count
                    if allUploaded {
                        onLog("Upload watcher finished.")
                        break
                    }
                    drainCount += 1
                    if drainCount > 15 {
                        onLog("Upload watcher stopping after drain timeout.")
                        break
                    }
                }

                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }
}
