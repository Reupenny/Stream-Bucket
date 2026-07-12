import SwiftUI

struct AppTabView: View {
    @StateObject private var state = ProcessorState()
    @StateObject private var liveServer = LiveServerProcess()   // Persists across tab switches
    @State private var selectedTab = 0

    private let tabs = [
        (title: "Convert", icon: "film.stack"),
        (title: "Upload",  icon: "arrow.up.to.line.circle"),
        (title: "Live",    icon: "dot.radiowaves.left.and.right")
    ]

    var body: some View {
        ZStack {
            switch selectedTab {
            case 0:
                ContentView()
                    .environmentObject(state)
            case 1:
                BucketBrowserView()
                    .environmentObject(state)
            case 2:
                LiveStreamView(server: liveServer)
                    .environmentObject(state)
            default:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 0) {
                    ForEach(0..<tabs.count, id: \.self) { index in
                        Button(action: { selectedTab = index }) {
                            HStack(spacing: 6) {
                                // Live indicator dot on the Live tab when running
                                if index == 2 && liveServer.isRunning {
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 7, height: 7)
                                } else {
                                    Image(systemName: tabs[index].icon)
                                        .imageScale(.medium)
                                }
                                Text(tabs[index].title)
                                    .font(.subheadline)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 12)
                            .background(selectedTab == index ? Color(.selectedContentBackgroundColor) : Color.clear)
                            .foregroundColor(selectedTab == index ? .white : (index == 2 && liveServer.isRunning ? .red : .primary))
                            .cornerRadius(5)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(2)
                .background(Color(.controlBackgroundColor))
                .cornerRadius(7)
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color(.controlColor), lineWidth: 1))
                .frame(width: 360)
            }
        }
        .onChange(of: liveServer.isRunning) { _ in updateBadge() }
        .onChange(of: state.isProcessing) { _ in updateBadge() }
        .onAppear { updateBadge() }
    }
    
    private func updateBadge() {
        if liveServer.isRunning {
            NSApplication.shared.dockTile.badgeLabel = "LIVE"
        } else if state.isProcessing {
            NSApplication.shared.dockTile.badgeLabel = "Converting"
        } else {
            NSApplication.shared.dockTile.badgeLabel = nil
        }
    }
}