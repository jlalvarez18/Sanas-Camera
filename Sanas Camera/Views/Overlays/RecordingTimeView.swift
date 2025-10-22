//
//  RecordingTimeView.swift
//  Sanas Camera
//
//  Created by Juan Alvarez on 10/22/25.
//

import SwiftUI

struct RecordingTimeView: View {
    let time: TimeInterval
    
    var body: some View {
        Text(time.formatted)
            .fontWeight(.medium)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color("Sanas Red"))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

extension TimeInterval {
    var formatted: String {
        let time = Int(self)
        let seconds = time % 60
        let minutes = (time / 60) % 60
        let hours = (time / 3600)
        let formatString = "%0.2d:%0.2d:%0.2d"
        return String(format: formatString, hours, minutes, seconds)
    }
}

#Preview {
    RecordingTimeView(time: 400)
        .preferredColorScheme(.dark)
}
