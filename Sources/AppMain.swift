import SwiftUI

@main
struct HLSBatchProcessorApp: App {
    var body: some Scene {
        WindowGroup {
            AppTabView()
                .frame(minWidth: 1000, minHeight: 700)
        }
        .windowResizability(.contentMinSize)
    }
}
