//
//  SampleData.swift
//  Sanas Camera
//
//  Created by Juan Alvarez on 10/22/25.
//

import Foundation
import SwiftData

@MainActor
class SampleData {
    static let shared = SampleData()
    
    let modelContainer: ModelContainer
    
    var context: ModelContext {
        modelContainer.mainContext
    }
    
    private init() {
        let schema = Schema([
            VideoItem.self
        ])
        
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        
        do {
            modelContainer = try ModelContainer(for: schema, configurations: [config])
            
            insertSampleData()
            
            try context.save()
        } catch {
            fatalError("caould not create ModelContainer: \(error)")
        }
    }
    
    private func insertSampleData() {
        let item1 = VideoItem(timestamp: Date(), filePath: "http://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4", thumbFilePath: "https://fastly.picsum.photos/id/16/400/711.jpg?hmac=OkXiUCLo5f9ipTebcftscPJqZhNP5oCzdbiRPvb2Jpo")
        let item2 = VideoItem(timestamp: Date().addingTimeInterval(200), filePath: "", thumbFilePath: "https://fastly.picsum.photos/id/28/400/711.jpg?hmac=gQKhkVoZNBL6IucovMKjF8Gs1pug4MeShrWn9C26BZI")
        
        context.insert(item1)
        context.insert(item2)
    }
}
