import Foundation

class SpriteSheetGenerator {
    static func generateVTT(duration: Double, interval: Double, cols: Int, rows: Int, tileWidth: Int = 160, tileHeight: Int = 90, outputURL: URL) throws {
        var vtt = "WEBVTT\n\n"
        
        let totalTilesPerImage = cols * rows
        var currentTime: Double = 0
        var tileIndex = 0
        var imageIndex = 1
        
        while currentTime < duration {
            let endTime = min(currentTime + interval, duration)
            
            let col = tileIndex % cols
            let row = tileIndex / cols
            
            let x = col * tileWidth
            let y = row * tileHeight
            
            let imageName = String(format: "sprites_%03d.jpg", imageIndex)
            
            vtt += "\(formatTime(currentTime)) --> \(formatTime(endTime))\n"
            vtt += "\(imageName)#xywh=\(x),\(y),\(tileWidth),\(tileHeight)\n\n"
            
            currentTime += interval
            tileIndex += 1
            
            if tileIndex >= totalTilesPerImage {
                tileIndex = 0
                imageIndex += 1
            }
        }
        
        try vtt.write(to: outputURL, atomically: true, encoding: .utf8)
    }
    
    private static func formatTime(_ seconds: Double) -> String {
        let hrs = Int(seconds) / 3600
        let mins = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        let millis = Int((seconds - floor(seconds)) * 1000)
        return String(format: "%02d:%02d:%02d.%03d", hrs, mins, secs, millis)
    }
}
