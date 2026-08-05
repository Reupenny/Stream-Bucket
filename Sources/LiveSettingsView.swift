import SwiftUI

/// Global Live stream settings. Sets the defaults applied to every new stream.
/// Opened in its own window from the Live tab's "Global Settings" button.
struct LiveSettingsView: View {
    @EnvironmentObject var state: ProcessorState
    @Environment(\.dismiss) private var dismiss

    // Local editable copy so Cancel/discard is implicit (changes apply live).
    @State private var defaults: LiveDefaults

    init() {
        // Read the current defaults lazily via a wrapper so we don't need the
        // environment object at init time.
        _defaults = State(initialValue: LiveDefaults())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Live Stream Defaults")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("These settings are applied to new streams. Existing streams keep their own settings, which you can edit in each stream's detail view.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    // Resolutions
                    GroupBox("Streaming Resolutions") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Selected resolutions are encoded concurrently (higher CPU).")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Toggle("1080p (Full HD)", isOn: $defaults.enable1080p)
                            Toggle("720p (HD)", isOn: $defaults.enable720p)
                            Toggle("480p (SD)", isOn: $defaults.enable480p)
                            Toggle("240p (Low)", isOn: $defaults.enable240p)
                        }
                        .padding(6)
                    }

                    // HLS Segment Settings
                    GroupBox("HLS Segment Settings") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Segment Length:")
                                    .font(.caption).foregroundColor(.secondary)
                                Spacer()
                                Stepper("\(defaults.segmentLength)s", value: $defaults.segmentLength, in: 2...10)
                            }
                            HStack {
                                Text("Playlist Size:")
                                    .font(.caption).foregroundColor(.secondary)
                                Spacer()
                                Stepper(defaults.playlistSize == 0 ? "Keep All" : "\(defaults.playlistSize) segs", value: $defaults.playlistSize, in: 0...60)
                            }
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Buffer Segments:")
                                        .font(.caption).foregroundColor(.secondary)
                                    Text("Delay before playlist is published")
                                        .font(.caption2)
                                        .foregroundColor(.secondary.opacity(0.7))
                                }
                                Spacer()
                                Stepper("\(defaults.bufferSegments)", value: $defaults.bufferSegments, in: 1...10)
                            }
                        }
                        .padding(6)
                    }

                    // Recording Settings
                    GroupBox("Recording Settings") {
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle("Record streams to S3 by default", isOn: $defaults.recordToS3)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Default Base Folder Path:")
                                    .font(.caption).foregroundColor(.secondary)
                                TextField("live_recordings", text: $defaults.s3Folder)
                            }
                        }
                        .padding(6)
                    }

                    // YouTube RTMP Defaults
                    GroupBox("YouTube RTMP Defaults") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Applied to new streams as a YouTube destination when a stream key is set.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("RTMP URL:")
                                    .font(.caption).foregroundColor(.secondary)
                                TextField("rtmp://a.rtmp.youtube.com/live2", text: $defaults.youtubeRtmpUrl)
                                    .textFieldStyle(.roundedBorder)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Stream Key:")
                                    .font(.caption).foregroundColor(.secondary)
                                SecureField("YouTube stream key", text: $defaults.youtubeStreamKey)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                        .padding(6)
                    }
                }
                .padding()
            }

            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 520, height: 600)
        .onAppear { defaults = state.liveDefaults }
        .onChange(of: defaults) { _ in state.liveDefaults = defaults }
    }
}
