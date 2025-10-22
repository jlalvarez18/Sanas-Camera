//
//  ContentView.swift
//  Sanas Camera
//
//  Created by Juan Alvarez on 10/22/25.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var items: [Item]

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                Image("sanas_logo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 24)
                    .accessibilityHidden(true)

                CameraPreviewView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 24)

                CameraFooterView()
            }
            .background(Color.black) // keep NavView from changing bg
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
    }

    private func addItem() {
        withAnimation {
            let newItem = Item(timestamp: Date())
            modelContext.insert(newItem)
        }
    }

    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(items[index])
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Item.self, inMemory: true)
}
