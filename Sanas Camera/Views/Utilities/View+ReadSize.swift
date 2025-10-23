//
//  View+ReadSize.swift
//  Sanas Camera
//
//  Created by Juan Alvarez on 10/23/25.
//

import SwiftUI

extension View {
    // This utility function helps with reading the current size of the View
    func readSize(onChange: @escaping (CGSize) -> Void) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: SizePreferenceKey.self,
                    value: proxy.size
                )
            }
        )
        .onPreferenceChange(SizePreferenceKey.self, perform: onChange)
    }
}

private struct SizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {}
}
