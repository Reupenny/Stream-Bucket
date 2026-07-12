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
    
    func uploadFolder(folderURL: URL, videoName: String, onProgress: @escaping (Double) -> Void, onLog: @escaping (String) -> Void) async throws -> String {
        let fileManager = FileManager.default
        let enumerator = fileManager.enumerator(at: folderURL, includingPropertiesForKeys: [.isDirectoryKey])!
        
        var uploadFiles: [URL] = []
        for case let fileURL as URL in enumerator.allObjects {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.isDirectoryKey]),
                  let isDirectory = resourceValues.isDirectory, !isDirectory else { continue }
            uploadFiles.append(fileURL)
        }
        
        let totalFiles = uploadFiles.count
        if totalFiles == 0 { return "" }
        
        let safeVideoName = videoName.replacingOccurrences(of: " ", with: "_")
        
        for (index, fileURL) in uploadFiles.enumerated() {
            let relativePath = fileURL.path.replacingOccurrences(of: folderURL.path + "/", with: "")
            let safeRelPath = relativePath.replacingOccurrences(of: " ", with: "_")
            let s3Key = "\(targetFolder)\(safeVideoName)/\(safeRelPath)"
            let ext = fileURL.pathExtension.lowercased()
            
            var mimeType = "application/octet-stream"
            if ext == "m3u8" { mimeType = "application/vnd.apple.mpegurl" }
            else if ext == "ts" { mimeType = "video/MP2T" }
            else if ext == "jpg" || ext == "jpeg" { mimeType = "image/jpeg" }
            else if ext == "vtt" { mimeType = "text/vtt" }
            
            await uploadWithRetry(fileURL: fileURL, s3Key: s3Key, mimeType: mimeType, onLog: onLog)
            
            DispatchQueue.main.async {
                onProgress(Double(index + 1) / Double(totalFiles))
            }
        }
        
        let masterPlaylistPath = "\(targetFolder)\(safeVideoName)/master.m3u8"
        if !cdnUrl.isEmpty {
            let base = cdnUrl.hasSuffix("/") ? String(cdnUrl.dropLast()) : cdnUrl
            var key = masterPlaylistPath
            if !cdnPathToStrip.isEmpty, key.hasPrefix(cdnPathToStrip) {
                key = String(key.dropFirst(cdnPathToStrip.count))
                if key.hasPrefix("/") { key = String(key.dropFirst()) }
            }
            return "\(base)/\(key)"
        } else {
            return "https://\(client.endpoint)/\(client.bucket)/\(masterPlaylistPath)"
        }
    }
    
    private func uploadWithRetry(fileURL: URL, s3Key: String, mimeType: String, onLog: @escaping (String) -> Void, attempts: Int = 3) async {
        for attempt in 1...attempts {
            do {
                try await client.putObject(path: s3Key, fileURL: fileURL, contentType: mimeType)
                return
            } catch {
                if attempt == attempts {
                    DispatchQueue.main.async {
                        onLog("ERROR: Failed to upload \(s3Key) after \(attempts) attempts: \(error.localizedDescription)")
                    }
                } else {
                    // Small delay before retry
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }
        }
    }
}
