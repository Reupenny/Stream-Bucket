import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject private var state: ProcessorState
    
    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 280, ideal: 300, max: 320)
                .background(Color(NSColor.windowBackgroundColor))
        } detail: {
            mainDetail
                .background(Color(NSColor.controlBackgroundColor))
        }
    }
    
    // MARK: - Sidebar
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("VOD settings")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    // Encoding Presets
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Encoding Presets").font(.headline)
                        Picker("", selection: $state.selectedPreset) {
                            ForEach(EncodingPreset.allCases) { preset in
                                Text(preset.rawValue).tag(preset)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                    
                    // Resolutions
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Resolutions").font(.subheadline).foregroundColor(.secondary)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("1080p(Full HD)", isOn: $state.enable1080p)
                            Toggle("720p(HD)", isOn: $state.enable720p)
                            Toggle("480p(SD)", isOn: $state.enable480p)
                            Toggle("240p(Low)", isOn: $state.enable240p)
                        }
                            .padding(.top, 4)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.controlBackgroundColor)))
                    
                    // Audio
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Audio").font(.subheadline).foregroundColor(.secondary)
                        
                        HStack {
                            Text("Codec:")
                            Spacer()
                            Picker("", selection: $state.audioCodec) {
                                Text("AAC").tag("AAC")
                                Text("MP3").tag("MP3")
                            }
                            .labelsHidden()
                            .frame(width: 100)
                        }
                        
                        HStack {
                            Text("Bitrate:")
                            Slider(value: Binding(
                                get: { Double(state.audioBitrate.replacingOccurrences(of: "k", with: "")) ?? 128.0 },
                                set: { state.audioBitrate = "\(Int($0))k" }
                            ), in: 64...320, step: 32)
                        }
                    }
                    
                    // Thumbnails
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Thumbnails", isOn: $state.generateThumbnails)
                            .font(.headline)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Advanced options:").font(.subheadline)
                            Toggle("poster.jpg", isOn: $state.generatePoster)
                            Toggle("Generate Sprite Sheets", isOn: $state.generateSpriteSheets)
                            Toggle("thumbnails.vtt", isOn: $state.generateVTT)
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.controlBackgroundColor)))
                        .disabled(!state.generateThumbnails)
                        
                        HStack {
                            Text("Segment Length:")
                            Stepper(value: $state.segmentLength, in: 2...20) {
                                Text("\(state.segmentLength)")
                            }
                        }
                        .padding(.top, 4)
                    }
                    
                    // S3 Auto-Upload
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Upload to Cloud After Encoding", isOn: $state.enableS3Upload)
                            .font(.headline)
                        
                        if state.enableS3Upload {
                            Toggle("Simultaneous Transcode & Upload", isOn: $state.simultaneousMode)
                                .font(.subheadline)
                                .padding(.bottom, 4)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                if state.s3Profiles.isEmpty {
                                    Text("No profiles configured. Add one in the Upload tab.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("Destination Profile:").font(.subheadline)
                                    Picker("", selection: $state.selectedProfileId) {
                                        ForEach(state.s3Profiles) { profile in
                                            Text(profile.name).tag(Optional(profile.id))
                                        }
                                    }
                                    .labelsHidden()
                                    .frame(maxWidth: .infinity)
                                    
                                    if let profile = state.activeProfile {
                                        Text("Bucket: \(profile.bucket)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.controlBackgroundColor)))
                        }
                    }
                }
                .padding()
            }
            
            // Start Batch Button
            Button(action: startProcessing) {
                Text(state.isProcessing ? "Processing..." : "Start Batch")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill((state.isProcessing || state.queue.isEmpty || state.outputFolder == nil || !state.queue.contains(where: { $0.isEnabled })) ? Color.blue.opacity(0.5) : Color.blue)
            )
            .disabled(state.isProcessing || state.queue.isEmpty || state.outputFolder == nil || !state.queue.contains(where: { $0.isEnabled }))
            .padding()
        }
    }
    
    // MARK: - Main Detail View
    private var mainDetail: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Batch Conversion Queue")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            HStack {
                Button(action: { selectInput(directoriesOnly: false) }) {
                    Text("Add Files")
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.blue))
                
                Button(action: { selectInput(directoriesOnly: true) }) {
                    Text("Add Folder")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(NSColor.controlColor)))
                
                Spacer()
                
                Button(action: { state.outputFolder = selectFolder(directoriesOnly: true) }) {
                    Text(state.outputFolder != nil ? "Output: \(state.outputFolder!.lastPathComponent)" : "Select Local Output Folder")
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.controlColor)))
            }
            
            Text("Batch Queue Table")
                .font(.headline)
                .padding(.top, 8)
            
            // Queue Table
            Table($state.queue) {
                TableColumn("Enabled") { $item in
                    Toggle("", isOn: $item.isEnabled).labelsHidden()
                }.width(60)
                
                TableColumn("Filename") { $item in
                    Text(item.filename).foregroundColor(item.isEnabled ? .primary : .secondary)
                }
                
                TableColumn("Input Path (optional)") { $item in
                    Text(item.url.path).lineLimit(1).truncationMode(.middle).foregroundColor(.secondary)
                }
                
                TableColumn("Progress") { $item in
                    if item.status == "Processing" || item.status == "Converting" || item.status == "Uploading" {
                        ProgressView(value: state.progress)
                            .tint(.blue)
                    } else if item.status == "Done" {
                        ProgressView(value: 1.0)
                            .tint(.green)
                    } else {
                        ProgressView(value: 0.0)
                    }
                }
                
                TableColumn("Status") { $item in
                    Text(item.status == "Ready" ? "Waiting" : item.status)
                        .foregroundColor(statusColor(item.status))
                }.width(100)
                
                TableColumn("Action") { $item in
                    if let url = item.uploadUrl {
                        Button("Copy Master URL") {
                            let pb = NSPasteboard.general
                            pb.clearContents()
                            pb.setString(url, forType: .string)
                        }
                        .buttonStyle(.link)
                    }
                }.width(120)
            }
            .frame(maxHeight: .infinity)
            .background(Color.white)
            .cornerRadius(8)
            
            Text("Progress & Logs")
                .font(.headline)
            
            progressSection
        }
        .padding()
    }
    
    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(state.isProcessing ? "Processing: \(state.currentFile)" : "Ready")
                .font(.headline)

            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Encoding:")
                    ProgressView(value: state.progress)
                        .tint(.blue)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Uploading:")
                    ProgressView(value: state.uploadProgress)
                        .tint(state.enableS3Upload ? .blue : .gray)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Process Logs:")
                ScrollView {
                    Text(state.logs)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 120)
                .background(Color.white)
                .cornerRadius(4)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray.opacity(0.2)))
            }

            HStack(spacing: 12) {
                Button(action: exportLogs) {
                    Label("Export Logs", systemImage: "doc.text")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(NSColor.controlColor)))
                .disabled(state.logs.isEmpty)

                Button(action: retryFailed) {
                    Label("Retry Failed", systemImage: "arrow.triangle.2.circlepath")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(NSColor.controlColor)))
                .disabled(state.isProcessing || !state.queue.contains(where: { $0.status == "Failed" }))
            }
        }
        .padding(16)
        .background(Color(NSColor.underPageBackgroundColor))
        .cornerRadius(12)
    }
    
    // MARK: - Helpers
    
    private func statusColor(_ status: String) -> Color {
        switch status {
        case "Done": return .primary
        case "Processing", "Converting", "Uploading": return .primary
        case "Failed": return .red
        default: return .primary
        }
    }
    
    private func selectFolder(directoriesOnly: Bool = false) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = !directoriesOnly
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK {
            return panel.url
        }
        return nil
    }
    
    private func selectInput(directoriesOnly: Bool) {
        guard let url = selectFolder(directoriesOnly: directoriesOnly) else { return }
        if directoriesOnly {
            state.inputFolder = url
        }
        
        let fileManager = FileManager.default
        var isDir: ObjCBool = false
        if fileManager.fileExists(atPath: url.path, isDirectory: &isDir) {
            let supportedExtensions = ["mp4", "mov", "mkv", "avi"]
            
            if isDir.boolValue {
                guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey]) else { return }
                for case let fileURL as URL in enumerator.allObjects {
                    guard let resourceValues = try? fileURL.resourceValues(forKeys: [.isDirectoryKey]),
                          let isDirectory = resourceValues.isDirectory, !isDirectory else { continue }
                    
                    if supportedExtensions.contains(fileURL.pathExtension.lowercased()) {
                        let filename = fileURL.deletingPathExtension().lastPathComponent
                        let qFile = QueuedFile(url: fileURL, filename: filename, metadata: "Video File")
                        state.queue.append(qFile)
                    }
                }
            } else {
                if supportedExtensions.contains(url.pathExtension.lowercased()) {
                    let filename = url.deletingPathExtension().lastPathComponent
                    let qFile = QueuedFile(url: url, filename: filename, metadata: "Video File")
                    state.queue.append(qFile)
                }
            }
        }
    }
    
    private func exportLogs() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "hls-batch-log.txt"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? state.logs.write(to: url, atomically: true, encoding: .utf8)
    }

    private func retryFailed() {
        // Reset all failed items back to Ready
        for idx in state.queue.indices where state.queue[idx].status == "Failed" {
            state.queue[idx].status = "Ready"
            state.queue[idx].uploadUrl = nil
        }
        startProcessing()
    }

    private func startProcessing() {
        guard let output = state.outputFolder else { return }
        state.isProcessing = true
        state.progress = 0.0
        state.uploadProgress = 0.0
        state.logs = "Starting batch process...\n"
        let processor = BatchProcessor(state: state)
        Task {
            await processor.process(outputFolder: output)
            state.isProcessing = false
        }
    }
}
