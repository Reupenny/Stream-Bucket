import Foundation
import SwiftUI

struct QueuedFile: Identifiable {
    let id = UUID()
    var url: URL
    var filename: String
    var metadata: String
    
    var isEnabled: Bool = true
    var status: String = "Ready" // Ready, Processing, Done, Failed
    var uploadUrl: String?
}
