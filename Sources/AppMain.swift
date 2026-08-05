import SwiftUI

@main
struct HLSBatchProcessorApp: App {
    @StateObject private var state = ProcessorState()
    @StateObject private var liveServer = LiveServerProcess()

    var body: some Scene {
        WindowGroup {
            AppTabView()
                .environmentObject(state)
                .environmentObject(liveServer)
                .frame(minWidth: 1000, minHeight: 700)
        }
        .windowResizability(.contentMinSize)
    }
}
