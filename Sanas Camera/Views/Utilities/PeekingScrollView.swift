//
//  PeekingScrollView.swift
//  Sanas Camera
//
//  Created by Juan Alvarez on 10/23/25.
//

import SwiftUI

struct PeekingScrollView<Item, Cell: View>: View {
    private let items: [Item]
    private var contentMargin: CGFloat
    private let spacing: CGFloat
    @ViewBuilder private let makeCell: (Int, Item) -> Cell
    
    @State private var height: CGFloat = 1 // The change will not be triggered if set to 0
    
    init(_ items: [Item],
         contentMargin: CGFloat = 10.0,
         spacing: CGFloat = 10.0,
         @ViewBuilder makeCell: @escaping (Int, Item) -> Cell)
    {
        self.items = items
        self.contentMargin = contentMargin
        self.spacing = spacing
        self.makeCell = makeCell
    }
    
    var body: some View {
        GeometryReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(Array(zip(items.indices, items)), id: \.0) { index, item in
                        makeCell(index, item)
                            .padding(spacing / 2)
                    }
                    .readSize { size in
                        self.height = max(size.height, self.height)
                    }
                    .frame(width: proxy.size.width > (contentMargin * 2) ? proxy.size.width - (contentMargin * 2) : 0)
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .safeAreaPadding(.horizontal, contentMargin)
        }
        .frame(height: height)
    }
}
//
//#Preview {
//    PeekingScrollView()
//}
