import SwiftUI
import AppKit

struct LiveStreamView: View {
    @EnvironmentObject var state: ProcessorState
    @ObservedObject var server: LiveServerProcess
    
    @State private var showCreateSheet = false
    
    var selectedStream: ScheduledStream? {
        state.scheduledStreams.first { $0.id == state.selectedStreamId }
    }
    
    var defaultCdnUrl: String {
        guard let profile = state.activeProfile, !profile.cdnUrl.isEmpty else {
            return "(Configure a CDN URL in the Upload tab first)"
        }
        let base = profile.cdnUrl.hasSuffix("/") ? String(profile.cdnUrl.dropLast()) : profile.cdnUrl
        let folder = state.liveS3Folder.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let strip = profile.cdnPathToStrip
        var path = folder.isEmpty ? "stream/master.m3u8" : "\(folder)/stream/master.m3u8"
        if !strip.isEmpty, path.hasPrefix(strip) {
            path = String(path.dropFirst(strip.count))
            if path.hasPrefix("/") { path = String(path.dropFirst()) }
        }
        return "\(base)/\(path)"
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
        .sheet(isPresented: $showCreateSheet) {
            CreateStreamSheet(isPresented: $showCreateSheet, server: server) { stream in
                state.scheduledStreams.append(stream)
                state.selectedStreamId = stream.id
            }
            .environmentObject(state)
        }
    }
    
    // MARK: - Sidebar
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Live Streams")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    // Server Status with encoder connection state
                    HStack {
                        Circle()
                            .fill(server.clientConnected ? Color.green : (server.isRunning ? Color.orange : Color.red))
                            .frame(width: 10, height: 10)
                        Text(server.clientConnected ? "Encoder Connected" : (server.isRunning ? "Waiting for Encoder…" : "Server Stopped"))
                            .font(.subheadline)
                            .foregroundColor(server.clientConnected ? .green : (server.isRunning ? .orange : .secondary))
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))
                    
                    // Server Start/Stop
                    VStack(spacing: 8) {
        Button(action: {
                            if let stream = selectedStream {
                                server.startServer(state: state, streamTitle: stream.title, streamKey: stream.streamKey)
                            } else {
                                server.startServer(state: state, streamTitle: nil, streamKey: nil)
                            }
                        }) {
                            Text(server.isRunning ? "Restart" : "Start Server")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        .background(RoundedRectangle(cornerRadius: 14).fill(server.isRunning ? Color.orange : Color.blue))
                        .contentShape(Rectangle())
                        
                        Button(action: { server.stopServer() }) {
                            Text("Stop Server")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color(NSColor.controlColor)))
                        .contentShape(Rectangle())
                        .disabled(!server.isRunning)
                    }
                    
                    Divider()
                    
                    // Scheduled Streams List
                    HStack {
                        Text("Scheduled Streams")
                            .font(.headline)
                        Spacer()
                        Button(action: { showCreateSheet = true }) {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.blue)
                                .font(.title3)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    if state.scheduledStreams.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "calendar.badge.plus")
                                .font(.system(size: 32))
                                .foregroundColor(.secondary)
                            Text("No streams scheduled.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("Press + to create one")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    } else {
                        VStack(spacing: 4) {
                            ForEach(state.scheduledStreams.sorted(by: { $0.date < $1.date })) { stream in
                                StreamRowView(
                                    stream: stream,
                                    isSelected: state.selectedStreamId == stream.id,
                                    onSelect: { state.selectedStreamId = stream.id },
                                    onDelete: {
                                        state.scheduledStreams.removeAll { $0.id == stream.id }
                                        if state.selectedStreamId == stream.id { state.selectedStreamId = nil }
                                    }
                                )
                            }
                        }
                    }
                    
                    Divider()
                    
                    // Streaming Resolutions
                    GroupBox("Streaming Resolutions") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Selected resolutions will be encoded concurrently (requires higher CPU).")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Toggle("1080p (Full HD)", isOn: $state.enable1080p)
                            Toggle("720p (HD)", isOn: $state.enable720p)
                            Toggle("480p (SD)", isOn: $state.enable480p)
                            Toggle("240p (Low)", isOn: $state.enable240p)
                        }
                        .padding(6)
                    }
                    
                    GroupBox("HLS Segment Settings") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Segment Length:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Stepper("\(state.liveSegmentLength)s", value: $state.liveSegmentLength, in: 2...10)
                            }
                            
                            HStack {
                                Text("Playlist Size:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Stepper(state.livePlaylistSize == 0 ? "Keep All" : "\(state.livePlaylistSize) segs", value: $state.livePlaylistSize, in: 0...60)
                            }
                            
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Buffer Segments:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("Delay before playlist is published")
                                        .font(.caption2)
                                        .foregroundColor(.secondary.opacity(0.7))
                                }
                                Spacer()
                                Stepper("\(state.liveBufferSegments)", value: $state.liveBufferSegments, in: 1...10)
                            }
                        }
                        .padding(6)
                    }
                    
                    // S3 Recording Settings
                    GroupBox("Recording Settings") {
                        VStack(alignment: .leading, spacing: 10) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Destination Bucket:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Picker("", selection: $state.selectedProfileId) {
                                    ForEach(state.s3Profiles) { profile in
                                        Text(profile.name).tag(Optional(profile.id))
                                    }
                                }
                                .labelsHidden()
                                .frame(maxWidth: .infinity)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Base Folder Path:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                TextField("/live_recordings", text: $state.liveS3Folder)
                            }
                        }
                        .padding(6)
                    }
                }
                .padding()
            }
            
            // Bottom action bar
            HStack {
                Button(action: exportLogs) {
                    Label("Export Logs", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.controlColor)))
                .contentShape(Rectangle())
            }
            .padding()
        }
    }
    
    // MARK: - Main Detail
    private var mainDetail: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let stream = selectedStream {
                StreamDetailView(stream: stream, server: server)
            } else {
                dashboardView
            }
        }
    }
    
    private var dashboardView: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Live Dashboard")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            HStack(spacing: 24) {
                StatView(title: "Active Streams", value: "\(server.activeStreams)")
                StatView(title: "Total Bitrate", value: server.totalBitrate)
                StatView(title: "HLS Outputs", value: "\(server.activeHLSOutputs)")
                StatView(title: "Viewers", value: "\(server.viewers)")
            }
            .padding(.vertical, 8)
            
            // Encoder connected banner
            if server.isRunning && server.clientConnected {
                HStack(spacing: 10) {
                    Circle().fill(.green).frame(width: 10, height: 10)
                    Text("Encoder is actively streaming")
                        .font(.subheadline)
                        .foregroundColor(.green)
                    Spacer()
                    Text(server.totalBitrate)
                        .font(.subheadline.monospacedDigit())
                        .foregroundColor(.secondary)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.green.opacity(0.1)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.green.opacity(0.3), lineWidth: 1))
            } else if server.isRunning {
                HStack(spacing: 10) {
                    ProgressView().scaleEffect(0.7)
                    Text("Waiting for OBS or encoder to connect to rtmp://localhost:1935/live/stream")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.1)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.orange.opacity(0.3), lineWidth: 1))
            }
            
            // Upcoming stream banner
            if let nextStream = state.scheduledStreams.sorted(by: { $0.date < $1.date }).first(where: { $0.date > Date() }) {
                upcomingBanner(stream: nextStream)
            }
            
            // Default Stream URL Copier
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Default Fallback Stream URL (/stream)")
                        .font(.caption).foregroundColor(.secondary)
                    Text(defaultCdnUrl)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)
                }
                Spacer()
                CopyButton(text: defaultCdnUrl)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))
            
            if !server.isRunning && server.logs.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        .font(.system(size: 64))
                        .foregroundColor(.secondary)
                    Text("Start the server to load the dashboard.")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Or select a scheduled stream from the sidebar to see its details.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("Real-time Server Logs")
                    .font(.headline)
                
                Table(server.logs) {
                    TableColumn("Timestamp") { log in
                        Text(formatDate(log.timestamp))
                            .font(.system(.caption, design: .monospaced))
                    }.width(140)
                    
                    TableColumn("Level") { log in
                        Text(log.level)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(logColor(log.level))
                    }.width(60)
                    
                    TableColumn("Thread") { log in
                        Text(log.thread)
                            .font(.system(.caption, design: .monospaced))
                    }.width(80)
                    
                    TableColumn("Message") { log in
                        Text(log.message)
                            .font(.system(.caption, design: .monospaced))
                    }
                }
                .frame(maxHeight: .infinity)
                .cornerRadius(8)
            }
        }
        .padding()
    }
    
    private func upcomingBanner(stream: ScheduledStream) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "clock.fill")
                .foregroundColor(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Next Stream: \(stream.title)")
                    .font(.headline)
                Text(stream.date, style: .relative)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button("Select") {
                state.selectedStreamId = stream.id
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange.opacity(0.4), lineWidth: 1))
    }
    
    private func logColor(_ level: String) -> Color {
        switch level {
        case "ERROR": return .red
        case "WARN": return .orange
        default: return .primary
        }
    }
    
    // MARK: - Helpers
    private func exportLogs() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "hls-live-log.txt"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let logText = server.logs.reversed().map { "[\(formatDate($0.timestamp))] [\($0.level)] [\($0.thread)] \($0.message)" }.joined(separator: "\n")
        try? logText.write(to: url, atomically: true, encoding: .utf8)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
}

// MARK: - Stream Row View
private struct StreamRowView: View {
    let stream: ScheduledStream
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(stream.title)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Image(systemName: stream.date > Date() ? "clock" : "checkmark.circle")
                        .font(.caption2)
                        .foregroundColor(stream.date > Date() ? .orange : .green)
                    Text(stream.date, style: .date)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(stream.date, style: .time)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            if isSelected {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.blue.opacity(0.15) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.blue.opacity(0.4) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .contextMenu {
            Button("Delete Stream", role: .destructive, action: onDelete)
        }
    }
}

// MARK: - Stream Detail View
private struct StreamDetailView: View {
    let stream: ScheduledStream
    let server: LiveServerProcess
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(stream.title)
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        HStack(spacing: 6) {
                            Image(systemName: stream.date > Date() ? "clock.fill" : "checkmark.circle.fill")
                                .foregroundColor(stream.date > Date() ? .orange : .green)
                            Text(stream.date > Date() ? "Scheduled for " : "Aired ")
                                .foregroundColor(.secondary)
                            Text(stream.date, style: .date)
                            Text("at")
                                .foregroundColor(.secondary)
                            Text(stream.date, style: .time)
                        }
                        .font(.subheadline)
                        if stream.date > Date() {
                            Text("Starting in ")
                                .foregroundColor(.secondary)
                                .font(.subheadline)
                            + Text(stream.date, style: .relative)
                                .font(.subheadline)
                                .foregroundColor(.orange)
                        }
                    }
                    Spacer()
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.controlBackgroundColor)))
                
                // OBS Configuration
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("OBS / Streaming Software Configuration")
                            .font(.headline)
                        
                        Divider()
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("RTMP Server URL")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("rtmp://localhost:1935/live/stream")
                                    .font(.system(.body, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                            Spacer()
                            CopyButton(text: "rtmp://localhost:1935/live/stream")
                        }
                        
                        Divider()
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Stream Key")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(stream.streamKey)
                                    .font(.system(.body, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                            Spacer()
                            CopyButton(text: stream.streamKey)
                        }
                    }
                    .padding(8)
                }
                
                // Embeddable URLs
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Embeddable URLs")
                            .font(.headline)
                        Text("Use these URLs to embed the stream on your website before it goes live.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Divider()
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Master Playlist (m3u8)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(stream.cdnUrl)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                    .lineLimit(3)
                                    .truncationMode(.middle)
                            }
                            Spacer(minLength: 8)
                            CopyButton(text: stream.cdnUrl)
                        }
                    }
                    .padding(8)
                }
                
                Spacer(minLength: 40)
            }
            .padding()
        }
    }
}

// MARK: - Create Stream Sheet
struct CreateStreamSheet: View {
    @EnvironmentObject var state: ProcessorState
    @Binding var isPresented: Bool
    let server: LiveServerProcess
    let onCreate: (ScheduledStream) -> Void
    
    @State private var title = ""
    @State private var date = Date().addingTimeInterval(3600)
    
    var generatedStreamKey: String {
        let safe = title.replacingOccurrences(of: " ", with: "_").lowercased()
        return safe.isEmpty ? "stream" : safe
    }
    
    var generatedCdnUrl: String {
        guard let profile = state.activeProfile, !profile.cdnUrl.isEmpty else {
            return "(Configure a CDN URL in the Upload tab first)"
        }
        let base = profile.cdnUrl.hasSuffix("/") ? String(profile.cdnUrl.dropLast()) : profile.cdnUrl
        let folder = state.liveS3Folder.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let strip = profile.cdnPathToStrip
        var path = folder.isEmpty ? "\(generatedStreamKey)/master.m3u8" : "\(folder)/\(generatedStreamKey)/master.m3u8"
        if !strip.isEmpty, path.hasPrefix(strip) {
            path = String(path.dropFirst(strip.count))
            if path.hasPrefix("/") { path = String(path.dropFirst()) }
        }
        return "\(base)/\(path)"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Create Stream")
                .font(.title2)
                .fontWeight(.bold)
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Stream Title")
                    .font(.headline)
                TextField("e.g. Sunday Night Match", text: $title)
                    .textFieldStyle(.roundedBorder)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Scheduled Date & Time")
                    .font(.headline)
                DatePicker("", selection: $date, displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                    .datePickerStyle(.graphical)
            }
            
            GroupBox("Generated Stream Details") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Stream Key")
                                .font(.caption).foregroundColor(.secondary)
                            Text(generatedStreamKey)
                                .font(.system(.body, design: .monospaced))
                        }
                        Spacer()
                        CopyButton(text: generatedStreamKey)
                    }
                    Divider()
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Embeddable m3u8 URL")
                                .font(.caption).foregroundColor(.secondary)
                            Text(generatedCdnUrl)
                                .font(.system(.caption, design: .monospaced))
                                .lineLimit(2)
                        }
                        Spacer()
                        CopyButton(text: generatedCdnUrl)
                    }
                }
                .padding(6)
            }
            
            Spacer()
            
            HStack {
                Button("Cancel") { isPresented = false }
                    .buttonStyle(.plain)
                Spacer()
                Button("Create Stream") {
                    guard !title.isEmpty else { return }
                    let streamKey = generatedStreamKey
                    let stream = ScheduledStream(
                        title: title,
                        date: date,
                        streamKey: streamKey,
                        cdnUrl: generatedCdnUrl
                    )
                    
                    // Pre-generate M3U8 files in the background
                    Task {
                        await server.pregeneratePlaylists(state: state, streamKey: streamKey)
                    }
                    
                    onCreate(stream)
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 480, height: 520)
    }
}

private struct LabeledRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
                .fontWeight(.medium)
        }
        .font(.system(size: 13, design: .monospaced))
    }
}

private struct StatView: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text(value)
                .font(.largeTitle)
                .fontWeight(.bold)
        }
    }
}

// MARK: - Reusable Copy Button
struct CopyButton: View {
    let text: String
    @State private var copied = false
    
    var body: some View {
        Button(action: {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
        }) {
            HStack(spacing: 4) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                Text(copied ? "Copied!" : "Copy")
            }
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(copied ? Color.green.opacity(0.15) : Color(NSColor.controlColor)))
            .foregroundColor(copied ? .green : .primary)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(copied ? Color.green.opacity(0.4) : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.2), value: copied)
    }
}
