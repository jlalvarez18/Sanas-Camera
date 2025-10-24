//
//  VideoItem.swift
//  Sanas Camera
//
//  Created by Juan Alvarez on 10/22/25.
//

import Foundation
import SwiftData
import UIKit

@Model
final class VideoItem {
    var timestamp: Date
    var filePath: String
    var thumbFilePath: String

    init(timestamp: Date, filePath: String, thumbFilePath: String) {
        self.timestamp = timestamp
        self.filePath = filePath
        self.thumbFilePath = thumbFilePath
    }
    
    static func sampleData() -> [VideoItem] {
        let item1 = VideoItem(timestamp: Date(), filePath: "https://video-previews.elements.envatousercontent.com/h264-video-previews/315b5d0f-cca5-41c0-824f-e99e2dcfbe6d/40108191.mp4", thumbFilePath: "https://fastly.picsum.photos/id/16/400/711.jpg?hmac=OkXiUCLo5f9ipTebcftscPJqZhNP5oCzdbiRPvb2Jpo")
        let item2 = VideoItem(timestamp: Date().addingTimeInterval(200), filePath: "http://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4", thumbFilePath: "https://fastly.picsum.photos/id/28/400/711.jpg?hmac=gQKhkVoZNBL6IucovMKjF8Gs1pug4MeShrWn9C26BZI")
        
        return [item1, item2]
    }
}

// MARK: - VideoItem helpers

extension VideoItem {
    // Documents directory URL
    private var documentsDir: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }
    
    // Build a local URL for a possibly filename-only path.
    // Supports legacy absolute file URLs (file:///...) and new filename-only values.
    private func localURL(from storedPath: String) -> URL? {
        if let url = URL(string: storedPath), url.isFileURL {
            // Legacy absolute file URL
            return url
        } else if !storedPath.isEmpty {
            // Treat as filename relative to Documents
            return documentsDir.appendingPathComponent(storedPath, isDirectory: false)
        } else {
            return nil
        }
    }
    
    // Local video URL using filename-based storage (or legacy absolute)
    var localVideoURL: URL? {
        localURL(from: filePath)
    }
    
    // Local thumbnail URL using filename-based storage (or legacy absolute)
    var localThumbURL: URL? {
        localURL(from: thumbFilePath)
    }
    
    var localThumbExists: Bool {
        guard let url = localThumbURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }
    
    var thumbImage: UIImage? {
        guard let url = localThumbURL else { return nil }
        guard FileManager.default.fileExists(atPath: url.path) else {
            #if DEBUG
            print("VideoItem: Local thumbnail missing at path: \(url.path)")
            #endif
            return nil
        }
        return UIImage(contentsOfFile: url.path)
    }
    
    // Remote thumbnail URL (only http/https)
    var remoteThumbURL: URL? {
        guard let url = URL(string: thumbFilePath),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else {
            return nil
        }
        return url
    }
    
    // Remote video URL (only http/https)
    var remoteVideoURL: URL? {
        guard let url = URL(string: filePath),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else {
            return nil
        }
        return url
    }
    
    var debugThumbDescription: String {
        if let local = localThumbURL {
            return "local: \(local.path) exists=\(localThumbExists)"
        } else if let remote = remoteThumbURL {
            return "remote: \(remote.absoluteString)"
        } else {
            return "invalid or empty path: \(thumbFilePath)"
        }
    }
}
