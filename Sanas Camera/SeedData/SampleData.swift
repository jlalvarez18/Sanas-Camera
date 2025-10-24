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
        let items = VideoItem.sampleData()
        
        for item in items {
            context.insert(item)
        }
    }
}
