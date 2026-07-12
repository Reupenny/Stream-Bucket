import SwiftUI
import AppKit

struct BucketBrowserView: View {
    @EnvironmentObject var state: ProcessorState

    @State private var objects: [S3Object] = []
    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var prefix = ""
    @State private var prefixHistory: [String] = []
    @State private var isUploading = false
    @State private var uploadProgressText = ""
    @State private var uploadProgressValue: Double = 0.0
    @State private var totalUploadFiles = 0
    @State private var doneUploadFiles = 0
    @State private var connectionTestResult = ""
    @State private var isTestingConnection = false
    @State private var isDeleting = false
    @State private var checkedItems = Set<S3Object.ID>()

    // Editor State
    @State private var editingProfile: S3Profile?
    @State private var editingKeyId: String = ""
    @State private var editingAppKey: String = ""
    @State private var editingTargetFolder: String = ""
    @State private var editingCdnPathToStrip: String = ""

    private var client: S3Client? {
        guard let p = state.activeProfile, !p.endpoint.isEmpty, !p.bucket.isEmpty else { return nil }
        let keys = state.getActiveS3Keys()
        guard !keys.keyId.isEmpty, !keys.appKey.isEmpty else { return nil }
        return S3Client(endpoint: p.endpoint, bucket: p.bucket, accessKey: keys.keyId, secretKey: keys.appKey)
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 290, ideal: 310, max: 360)
                .background(Color(NSColor.windowBackgroundColor))
        } detail: {
            mainDetail
                .background(Color(NSColor.controlBackgroundColor))
        }
        .task {
            loadEditorState()
            await refresh()
        }
        .onChange(of: state.selectedProfileId) { _ in
            loadEditorState()
            connectionTestResult = ""
            prefix = ""
            prefixHistory.removeAll()
            Task { await refresh() }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("S3 Connections")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    // Connection list
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Connections").font(.headline)
                            Spacer()
                            Button(action: addProfile) {
                                Image(systemName: "plus")
                            }.buttonStyle(.plain)
                        }

                        List(selection: $state.selectedProfileId) {
                            ForEach(state.s3Profiles) { profile in
                                HStack {
                                    Image(systemName: "externaldrive.fill.badge.wifi")
                                        .foregroundColor(state.selectedProfileId == profile.id ? .blue : .secondary)
                                    Text(profile.name)
                                        .fontWeight(state.selectedProfileId == profile.id ? .semibold : .regular)
                                    Spacer()
                                }
                                .tag(profile.id)
                                .contextMenu {
                                    Button("Delete", role: .destructive) { state.deleteProfile(profile) }
                                }
                            }
                        }
                        .frame(height: 100)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                        .scrollContentBackground(.hidden)
                    }

                    // Profile editor
                    if editingProfile != nil {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Connection Settings").font(.headline)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Name:")
                                TextField("Profile Name", text: Binding(
                                    get: { editingProfile?.name ?? "" },
                                    set: { editingProfile?.name = $0 }
                                ))
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Endpoint:")
                                TextField("https://s3...backblazeb2.com", text: Binding(
                                    get: { editingProfile?.endpoint ?? "" },
                                    set: { editingProfile?.endpoint = $0 }
                                ))
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Bucket:")
                                TextField("my-bucket-name", text: Binding(
                                    get: { editingProfile?.bucket ?? "" },
                                    set: { editingProfile?.bucket = $0 }
                                ))
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Key ID:")
                                SecureField("Access Key ID", text: $editingKeyId)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("App Key:")
                                SecureField("Secret Access Key", text: $editingAppKey)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("CDN URL (Optional):")
                                TextField("https://cdn.example.com", text: Binding(
                                    get: { editingProfile?.cdnUrl ?? "" },
                                    set: { editingProfile?.cdnUrl = $0 }
                                ))
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Target Folder (Optional):")
                                TextField("e.g. video/", text: $editingTargetFolder)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("CDN Path to Strip (Optional):")
                                TextField("e.g. video/", text: $editingCdnPathToStrip)
                            }

                            // Test + Save
                            HStack(spacing: 8) {
                                Button(action: testConnection) {
                                    if isTestingConnection {
                                        ProgressView().scaleEffect(0.7).frame(width: 16, height: 16)
                                    } else {
                                        Text("Test")
                                    }
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlColor)))
                                .disabled(isTestingConnection)

                                Button("Save") { saveProfile() }
                                    .buttonStyle(.plain)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.blue))
                                    .frame(maxWidth: .infinity)
                            }

                            if !connectionTestResult.isEmpty {
                                Text(connectionTestResult)
                                    .font(.caption)
                                    .foregroundColor(connectionTestResult.hasPrefix("✅") ? .green : .red)
                            }
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.controlBackgroundColor)))
                    }
                }
                .padding()
            }
        }
    }

    // MARK: - Main Detail

    private var mainDetail: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Cloud File Explorer")
                .font(.largeTitle)
                .fontWeight(.bold)

            // Breadcrumb + toolbar
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "externaldrive").foregroundColor(.blue)
                    Button(action: navigateToRoot) { Text("root") }
                        .buttonStyle(.plain)
                        .foregroundColor(.blue)

                    ForEach(breadcrumbs, id: \.offset) { crumb in
                        Text("/").foregroundColor(.secondary)
                        Button(crumb.label) { navigateTo(prefix: crumb.prefix) }
                            .buttonStyle(.plain)
                            .foregroundColor(.blue)
                    }
                }
                .font(.system(size: 13, weight: .medium))

                Spacer()
                
                if !checkedItems.isEmpty {
                    Button(action: { Task { await deleteSelected() } }) {
                        Label("Delete Selected (\(checkedItems.count))", systemImage: "trash")
                            .padding(.horizontal, 8).padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.red.opacity(0.8)))
                    .foregroundColor(.white)
                    .disabled(isDeleting)
                }

                Button(action: { uploadFiles(files: true, directories: false) }) {
                    Label("Upload File", systemImage: "arrow.up.doc")
                        .padding(.horizontal, 8).padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(NSColor.controlColor)))
                .disabled(client == nil || isUploading || isDeleting)

                Button(action: { uploadFiles(files: false, directories: true) }) {
                    Label("Upload Folder", systemImage: "folder.badge.plus")
                        .padding(.horizontal, 8).padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(NSColor.controlColor)))
                .disabled(client == nil || isUploading || isDeleting)

                Button(action: { Task { await refresh() } }) {
                    Image(systemName: "arrow.clockwise")
                        .padding(.horizontal, 8).padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(NSColor.controlColor)))
                .disabled(isLoading || isDeleting)
            }

            // Upload progress bar
            if isUploading {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(uploadProgressText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(doneUploadFiles)/\(totalUploadFiles) files")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    ProgressView(value: uploadProgressValue)
                        .tint(.blue)
                }
                .padding(.vertical, 4)
            }

            // File table
            if client == nil {
                VStack(spacing: 12) {
                    Image(systemName: "externaldrive.badge.exclamationmark")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Add and save a connection profile in the sidebar.")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isLoading {
                ProgressView("Loading…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !errorMessage.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundColor(.orange)
                    Text(errorMessage).foregroundColor(.red).multilineTextAlignment(.center)
                    Button("Retry") { Task { await refresh() } }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if objects.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray").font(.largeTitle).foregroundColor(.secondary)
                    Text(prefix.isEmpty ? "Bucket is empty" : "No files in this folder")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let allChecked = !objects.isEmpty && checkedItems.count == objects.count
                VStack(spacing: 0) {
                    // "Select All" header row
                    HStack {
                        Toggle("", isOn: Binding(
                            get: { allChecked },
                            set: { selectAll in
                                if selectAll {
                                    checkedItems = Set(objects.map { $0.id })
                                } else {
                                    checkedItems.removeAll()
                                }
                            }
                        ))
                        .toggleStyle(CheckboxToggleStyle())
                        .frame(width: 20)
                        Text(allChecked ? "Deselect All" : "Select All")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(NSColor.controlBackgroundColor))

                    Divider()

                    Table(objects) {
                        TableColumn("") { obj in
                            Toggle("", isOn: Binding(
                                get: { checkedItems.contains(obj.id) },
                                set: { isSelected in
                                    if isSelected {
                                        checkedItems.insert(obj.id)
                                    } else {
                                        checkedItems.remove(obj.id)
                                    }
                                }
                            ))
                            .toggleStyle(CheckboxToggleStyle())
                        }.width(20)

                        TableColumn("Name") { obj in
                            HStack(spacing: 6) {
                                Image(systemName: iconFor(obj))
                                    .foregroundColor(obj.isVirtualFolder ? .blue : .primary)
                                if obj.isVirtualFolder {
                                    Button(displayName(obj)) { navigateTo(prefix: obj.key) }
                                        .buttonStyle(.plain)
                                        .foregroundColor(.blue)
                                } else {
                                    Text(displayName(obj))
                                }
                            }
                            .contextMenu {
                                if !obj.isVirtualFolder {
                                    Button {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(getURL(for: obj), forType: .string)
                                    } label: {
                                        Label("Copy Link", systemImage: "doc.on.doc")
                                    }
                                }
                                Button(role: .destructive) {
                                    Task { await deleteObject(obj) }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                        
                        TableColumn("Type") { obj in
                            Text(obj.isVirtualFolder ? "Folder" : URL(fileURLWithPath: obj.key).pathExtension.uppercased())
                                .foregroundColor(.secondary)
                        }.width(60)

                        TableColumn("Size") { obj in
                            Text(obj.isVirtualFolder ? "—" : formatBytes(obj.size))
                                .foregroundColor(.secondary)
                        }.width(80)

                        TableColumn("Modified") { obj in
                            Text(obj.isVirtualFolder ? "" : formatDate(obj.lastModified))
                                .foregroundColor(.secondary)
                        }.width(140)
                    }
                    .frame(maxHeight: .infinity)
                    .background(Color.white)
                    .cornerRadius(8)
                    .overlay(
                        Group {
                            if isDeleting {
                                ZStack {
                                    Color.black.opacity(0.2)
                                    ProgressView("Deleting...")
                                        .padding()
                                        .background(Color(NSColor.windowBackgroundColor))
                                        .cornerRadius(8)
                                        .shadow(radius: 10)
                                }
                            }
                        }
                    )
                }
            }
            // Master URL quick-copy
            if !objects.filter({ !$0.isVirtualFolder && $0.key.hasSuffix(".m3u8") }).isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Master Playlist URLs").font(.headline)
                    let m3u8s = objects.filter { !$0.isVirtualFolder && $0.key.hasSuffix(".m3u8") }
                    ForEach(m3u8s) { obj in
                        HStack {
                            Text(getURL(for: obj))
                                .lineLimit(1).truncationMode(.middle)
                                .font(.caption)
                            Spacer()
                            Button("Copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(getURL(for: obj), forType: .string)
                            }
                            .buttonStyle(.plain)
                            .font(.caption)
                        }
                    }
                    Button("Copy All") {
                        let all = m3u8s.map { getURL(for: $0) }.joined(separator: "\n")
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(all, forType: .string)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.blue))
                }
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }
        }
        .padding()
    }

    // MARK: - Profile Management

    private func loadEditorState() {
        if let p = state.activeProfile {
            editingProfile = p
            let keys = state.getActiveS3Keys()
            editingKeyId  = keys.keyId
            editingAppKey = keys.appKey
            editingTargetFolder = p.targetFolder
            editingCdnPathToStrip = p.cdnPathToStrip
        } else {
            editingProfile = nil
            editingKeyId  = ""
            editingAppKey = ""
            editingTargetFolder = ""
            editingCdnPathToStrip = ""
        }
    }

    private func saveProfile() {
        if var p = editingProfile {
            p.targetFolder = editingTargetFolder
            p.cdnPathToStrip = editingCdnPathToStrip
            state.updateProfile(p, keyId: editingKeyId, appKey: editingAppKey)
            Task { await refresh() }
        }
    }

    private func addProfile() {
        let p = S3Profile(name: "New Connection", endpoint: "", bucket: "", cdnUrl: "")
        state.s3Profiles.append(p)
        state.selectedProfileId = p.id
    }

    private func testConnection() {
        guard let c = client else {
            connectionTestResult = "❌ Save settings first"
            return
        }
        isTestingConnection = true
        connectionTestResult = ""
        Task {
            do {
                try await c.headBucket()
                await MainActor.run {
                    connectionTestResult = "✅ Connected successfully!"
                    isTestingConnection = false
                }
            } catch {
                await MainActor.run {
                    connectionTestResult = "❌ \(error.localizedDescription)"
                    isTestingConnection = false
                }
            }
        }
    }

    // MARK: - Data & Navigation

    private struct Crumb { let offset: Int; let label: String; let prefix: String }

    private var breadcrumbs: [Crumb] {
        let parts = prefix.split(separator: "/").map(String.init)
        var crumbs: [Crumb] = []
        for (i, p) in parts.enumerated() {
            let accumulated = parts[0...i].joined(separator: "/") + "/"
            crumbs.append(Crumb(offset: i, label: p, prefix: accumulated))
        }
        return crumbs
    }

    private func refresh() async {
        guard let c = client else { objects = []; return }
        isLoading = true
        errorMessage = ""
        do {
            objects = try await c.listObjects(prefix: prefix)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func navigateToRoot() {
        prefix = ""
        prefixHistory.removeAll()
        Task { await refresh() }
    }

    private func navigateTo(prefix newPrefix: String) {
        prefixHistory.append(prefix)
        prefix = newPrefix
        Task { await refresh() }
    }

    private func deleteObject(_ obj: S3Object) async {
        guard let c = client else { return }
        isDeleting = true
        defer { isDeleting = false }
        do {
            if obj.isVirtualFolder {
                try await c.deleteFolder(prefix: obj.key)
            } else {
                try await c.deleteObject(path: obj.key)
            }
            await refresh()
        } catch {
            errorMessage = "Delete failed: \(error.localizedDescription)"
        }
    }

    private func deleteSelected() async {
        guard let c = client else { return }
        isDeleting = true
        defer { isDeleting = false }
        let objectsToDelete = objects.filter { checkedItems.contains($0.id) }
        var hasError = false
        for obj in objectsToDelete {
            do {
                if obj.isVirtualFolder {
                    try await c.deleteFolder(prefix: obj.key)
                } else {
                    try await c.deleteObject(path: obj.key)
                }
            } catch {
                errorMessage = "Delete failed for \(obj.key): \(error.localizedDescription)"
                hasError = true
                break
            }
        }
        if !hasError {
            checkedItems.removeAll()
        }
        await refresh()
    }

    private func getURL(for obj: S3Object) -> String {
        guard let p = state.activeProfile else { return "" }
        var key = obj.key
        
        if !p.cdnUrl.isEmpty {
            let base = p.cdnUrl.hasSuffix("/") ? String(p.cdnUrl.dropLast()) : p.cdnUrl
            let strip = p.cdnPathToStrip
            if !strip.isEmpty, key.hasPrefix(strip) {
                key = String(key.dropFirst(strip.count))
                if key.hasPrefix("/") { key = String(key.dropFirst()) }
            }
            return "\(base)/\(key)"
        }
        return "https://\(p.endpoint)/\(p.bucket)/\(obj.key)"
    }

    private func uploadFiles(files: Bool, directories: Bool) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = files
        panel.canChooseDirectories = directories
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls
        guard let c = client else { return }

        isUploading = true
        uploadProgressValue = 0
        doneUploadFiles = 0

        Task {
            var filesToUpload: [(URL, String)] = []
            let fm = FileManager.default

            for url in urls {
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                    if let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey]) {
                        for case let fileURL as URL in enumerator.allObjects {
                            guard let rv = try? fileURL.resourceValues(forKeys: [.isDirectoryKey]),
                                  let isDirectory = rv.isDirectory, !isDirectory else { continue }
                            let relPath = fileURL.path.replacingOccurrences(of: url.deletingLastPathComponent().path + "/", with: "")
                            let safeRelPath = relPath.replacingOccurrences(of: " ", with: "_")
                            filesToUpload.append((fileURL, prefix + safeRelPath))
                        }
                    }
                } else {
                    let safeName = url.lastPathComponent.replacingOccurrences(of: " ", with: "_")
                    filesToUpload.append((url, prefix + safeName))
                }
            }

            totalUploadFiles = filesToUpload.count

            for (i, file) in filesToUpload.enumerated() {
                let (url, key) = file
                await MainActor.run {
                    uploadProgressText = "Uploading: \(url.lastPathComponent)"
                    uploadProgressValue = Double(i) / Double(max(totalUploadFiles, 1))
                    doneUploadFiles = i
                }
                let mime = mimeType(for: url.pathExtension)
                try? await c.putObject(path: key, fileURL: url, contentType: mime)
            }

            await MainActor.run {
                uploadProgressValue = 1.0
                doneUploadFiles = totalUploadFiles
                uploadProgressText = "Done!"
            }

            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run {
                isUploading = false
                uploadProgressText = ""
                uploadProgressValue = 0
            }
            await refresh()
        }
    }

    // MARK: - Helpers

    private func displayName(_ obj: S3Object) -> String {
        let rel = obj.key.hasPrefix(prefix) ? String(obj.key.dropFirst(prefix.count)) : obj.key
        // Strip trailing slash for display
        return rel.hasSuffix("/") ? String(rel.dropLast()) : (rel.isEmpty ? obj.key : rel)
    }

    private func iconFor(_ obj: S3Object) -> String {
        if obj.isVirtualFolder { return "folder.fill" }
        let ext = URL(fileURLWithPath: obj.key).pathExtension.lowercased()
        switch ext {
        case "mp4", "mov", "mkv", "ts": return "film"
        case "m3u8":                    return "doc.text.fill"
        case "jpg", "jpeg", "png":      return "photo"
        case "vtt":                     return "text.bubble"
        default:                        return "doc"
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func formatDate(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: iso) {
            let df = DateFormatter(); df.dateStyle = .medium; df.timeStyle = .short
            return df.string(from: d)
        }
        return iso
    }

    private func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "m3u8": return "application/vnd.apple.mpegurl"
        case "ts":   return "video/MP2T"
        case "mp4":  return "video/mp4"
        case "jpg", "jpeg": return "image/jpeg"
        case "png":  return "image/png"
        case "vtt":  return "text/vtt"
        default:     return "application/octet-stream"
        }
    }
}
