//
//  VideoItem.swift
//  Sanas Camera
//
//  Created by Juan Alvarez on 10/22/25.
//

import Foundation
import SwiftData

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
}
