import Foundation
import SwiftUI

// MARK: - Models

struct S3Profile: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var endpoint: String
    var bucket: String
    var cdnUrl: String
    var targetFolder: String = ""
    var cdnPathToStrip: String = ""
    
    var keychainKeyIdAccount: String { "s3KeyId_\(id.uuidString)" }
    var keychainAppKeyAccount: String { "s3AppKey_\(id.uuidString)" }
    
    enum CodingKeys: String, CodingKey {
        case id, name, endpoint, bucket, cdnUrl, targetFolder, cdnPathToStrip
    }
    
    init(id: UUID = UUID(), name: String, endpoint: String, bucket: String, cdnUrl: String, targetFolder: String = "", cdnPathToStrip: String = "") {
        self.id = id
        self.name = name
        self.endpoint = endpoint
        self.bucket = bucket
        self.cdnUrl = cdnUrl
        self.targetFolder = targetFolder
        self.cdnPathToStrip = cdnPathToStrip
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        endpoint = try container.decode(String.self, forKey: .endpoint)
        bucket = try container.decode(String.self, forKey: .bucket)
        cdnUrl = try container.decodeIfPresent(String.self, forKey: .cdnUrl) ?? ""
        targetFolder = try container.decodeIfPresent(String.self, forKey: .targetFolder) ?? ""
        cdnPathToStrip = try container.decodeIfPresent(String.self, forKey: .cdnPathToStrip) ?? ""
    }
}

struct ScheduledStream: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var date: Date
    var streamKey: String
    var cdnUrl: String
}

enum EncodingPreset: String, CaseIterable, Identifiable {
    case vodOptimized = "VOD Optimized"
    case streamingLite = "Streaming Lite"
    var id: String { rawValue }
}

@MainActor
class ProcessorState: ObservableObject {
    @Published var inputFolder: URL?
    @Published var outputFolder: URL?
    
    // File Queue
    @Published var queue: [QueuedFile] = []
    
    // VOD Settings
    @AppStorage("selectedPreset") var selectedPreset: EncodingPreset = .vodOptimized
    
    // Resolutions
    @AppStorage("enable1080p") var enable1080p: Bool = true
    @AppStorage("enable720p") var enable720p: Bool = true
    @AppStorage("enable480p") var enable480p: Bool = false
    @AppStorage("enable240p") var enable240p: Bool = false
    @AppStorage("add360p") var add360p: Bool = false
    
    // Audio & Segments
    @AppStorage("segmentLength") var segmentLength: Int = 6
    @AppStorage("audioCodec") var audioCodec: String = "AAC"
    @AppStorage("audioBitrate") var audioBitrate: String = "128k"
    
    // Thumbnails
    @AppStorage("generateThumbnails") var generateThumbnails: Bool = true
    @AppStorage("generatePoster") var generatePoster: Bool = true
    @AppStorage("generateSpriteSheets") var generateSpriteSheets: Bool = false
    @AppStorage("generateVTT") var generateVTT: Bool = false
    
    // Live Server Settings
    @AppStorage("liveS3Folder") var liveS3Folder: String = "/live_recordings"
    
    // S3 Settings
    @AppStorage("enableS3Upload") var enableS3Upload: Bool = false
    @AppStorage("simultaneousMode") var simultaneousMode: Bool = false
    @Published var s3Profiles: [S3Profile] = [] {
        didSet { saveProfiles() }
    }
    @Published var selectedProfileId: UUID? {
        didSet {
            cachedKeyId = nil
            cachedAppKey = nil
            if let id = selectedProfileId {
                UserDefaults.standard.set(id.uuidString, forKey: "selectedProfileId")
            } else {
                UserDefaults.standard.removeObject(forKey: "selectedProfileId")
            }
        }
    }
    
    @Published var connectionTestResult: String = ""
    
    // Progress and State
    @Published var isProcessing: Bool = false
    @Published var currentFile: String = ""
    @Published var progress: Double = 0.0 // 0 to 1
    @Published var uploadProgress: Double = 0.0 // 0 to 1
    
    @Published var logs: String = ""
    
    // Cached S3 Credentials
    private var cachedKeyId: String?
    private var cachedAppKey: String?
    
    @Published var scheduledStreams: [ScheduledStream] = [] {
        didSet { saveScheduledStreams() }
    }
    
    /// Persists selected stream across tab switches
    @Published var selectedStreamId: UUID? = nil
    // Live Stream Config
    @AppStorage("liveSegmentLength") var liveSegmentLength: Int = 4
    @AppStorage("livePlaylistSize") var livePlaylistSize: Int = 10
    @AppStorage("liveBufferSegments") var liveBufferSegments: Int = 3
    
    init() {
        loadProfiles()
        loadScheduledStreams()
    }
    
    // MARK: - S3 Profiles
    
    private func loadProfiles() {
        if let data = UserDefaults.standard.data(forKey: "s3Profiles"),
           let profiles = try? JSONDecoder().decode([S3Profile].self, from: data) {
            self.s3Profiles = profiles
        } else {
            // Migration for existing single-connection setup
            let legacyEndpoint = UserDefaults.standard.string(forKey: "s3Endpoint") ?? ""
            let legacyBucket = UserDefaults.standard.string(forKey: "s3Bucket") ?? ""
            let legacyCdnUrl = UserDefaults.standard.string(forKey: "s3CdnUrl") ?? ""
            let legacyKeyId = KeychainHelper.shared.readString(service: "HLSBatchProcessor", account: "s3KeyId") ?? ""
            let legacyAppKey = KeychainHelper.shared.readString(service: "HLSBatchProcessor", account: "s3AppKey") ?? ""
            
            if !legacyEndpoint.isEmpty {
                let defaultProfile = S3Profile(name: "Default Profile", endpoint: legacyEndpoint, bucket: legacyBucket, cdnUrl: legacyCdnUrl)
                self.s3Profiles = [defaultProfile]
                KeychainHelper.shared.saveString(legacyKeyId, service: "HLSBatchProcessor", account: defaultProfile.keychainKeyIdAccount)
                KeychainHelper.shared.saveString(legacyAppKey, service: "HLSBatchProcessor", account: defaultProfile.keychainAppKeyAccount)
                
                // Clear old legacy keys to prevent issues
                KeychainHelper.shared.delete(service: "HLSBatchProcessor", account: "s3KeyId")
                KeychainHelper.shared.delete(service: "HLSBatchProcessor", account: "s3AppKey")
                UserDefaults.standard.removeObject(forKey: "s3Endpoint")
                UserDefaults.standard.removeObject(forKey: "s3Bucket")
                UserDefaults.standard.removeObject(forKey: "s3CdnUrl")
            }
        }
        
        if let idString = UserDefaults.standard.string(forKey: "selectedProfileId"), let id = UUID(uuidString: idString) {
            self.selectedProfileId = id
        } else if let first = s3Profiles.first {
            self.selectedProfileId = first.id
        }
    }
    
    private func saveProfiles() {
        if let data = try? JSONEncoder().encode(s3Profiles) {
            UserDefaults.standard.set(data, forKey: "s3Profiles")
        }
    }
    
    var activeProfile: S3Profile? {
        s3Profiles.first { $0.id == selectedProfileId }
    }
    
    // Retrieve keys for active profile
    func getActiveS3Keys() -> (keyId: String, appKey: String) {
        if let keyId = cachedKeyId, let appKey = cachedAppKey {
            return (keyId, appKey)
        }
        guard let p = activeProfile else { return ("", "") }
        let keyId = KeychainHelper.shared.readString(service: "HLSBatchProcessor", account: p.keychainKeyIdAccount) ?? ""
        let appKey = KeychainHelper.shared.readString(service: "HLSBatchProcessor", account: p.keychainAppKeyAccount) ?? ""
        cachedKeyId = keyId
        cachedAppKey = appKey
        return (keyId, appKey)
    }
    
    func saveActiveS3Keys(keyId: String, appKey: String) {
        guard let p = activeProfile else { return }
        KeychainHelper.shared.saveString(keyId, service: "HLSBatchProcessor", account: p.keychainKeyIdAccount)
        KeychainHelper.shared.saveString(appKey, service: "HLSBatchProcessor", account: p.keychainAppKeyAccount)
        cachedKeyId = keyId
        cachedAppKey = appKey
    }
    
    func updateProfile(_ profile: S3Profile, keyId: String, appKey: String) {
        if let idx = s3Profiles.firstIndex(where: { $0.id == profile.id }) {
            s3Profiles[idx] = profile
        } else {
            s3Profiles.append(profile)
        }
        KeychainHelper.shared.saveString(keyId, service: "HLSBatchProcessor", account: profile.keychainKeyIdAccount)
        KeychainHelper.shared.saveString(appKey, service: "HLSBatchProcessor", account: profile.keychainAppKeyAccount)
        if selectedProfileId == profile.id {
            cachedKeyId = keyId
            cachedAppKey = appKey
        }
    }
    
    func deleteProfile(_ profile: S3Profile) {
        KeychainHelper.shared.delete(service: "HLSBatchProcessor", account: profile.keychainKeyIdAccount)
        KeychainHelper.shared.delete(service: "HLSBatchProcessor", account: profile.keychainAppKeyAccount)
        s3Profiles.removeAll { $0.id == profile.id }
        if selectedProfileId == profile.id {
            selectedProfileId = s3Profiles.first?.id
        }
    }
    
    // MARK: - Scheduled Streams
    
    private func loadScheduledStreams() {
        if let data = UserDefaults.standard.data(forKey: "scheduledStreams"),
           let streams = try? JSONDecoder().decode([ScheduledStream].self, from: data) {
            self.scheduledStreams = streams
        }
    }
    
    private func saveScheduledStreams() {
        if let data = try? JSONEncoder().encode(scheduledStreams) {
            UserDefaults.standard.set(data, forKey: "scheduledStreams")
        }
    }
    
    // MARK: - Actions
    
    func appendLog(_ message: String) {
        logs += "\(message)\n"
    }
    
    func updateQueueStatus(id: UUID, status: String, uploadUrl: String? = nil) {
        if let idx = queue.firstIndex(where: { $0.id == id }) {
            queue[idx].status = status
            if let url = uploadUrl {
                queue[idx].uploadUrl = url
            }
        }
    }
}

// Ensure enum can be stored in AppStorage
extension EncodingPreset: RawRepresentable {}
