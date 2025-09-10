//
//  DynamicLogoView.swift
//  Aeru
//
//  Created by Claude Code
//

import SwiftUI

struct DynamicLogoView: View {
    @Environment(\.colorScheme) private var colorScheme
    
    let size: CGFloat
    let cornerRadius: CGFloat
    let showGradientBorder: Bool
    
    init(size: CGFloat = 80, cornerRadius: CGFloat = 18, showGradientBorder: Bool = false) {
        self.size = size
        self.cornerRadius = cornerRadius
        self.showGradientBorder = showGradientBorder
    }
    
    var body: some View {
        Group {
            if colorScheme == .dark {
                Image("aeru-logo-dark")
                    .resizable()
            } else {
                Image("aeru-logo")
                    .resizable()
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay(
            Group {
                if showGradientBorder {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 3
                        )
                }
            }
        )
        .glassEffect(.regular, in: .rect(cornerRadius: 16.0))
        .animation(.easeInOut(duration: 0.3), value: colorScheme)
    }
}

#Preview {
    VStack(spacing: 20) {
        DynamicLogoView(size: 100, cornerRadius: 22, showGradientBorder: true)
        DynamicLogoView(size: 80, cornerRadius: 18, showGradientBorder: false)
        DynamicLogoView(size: 60, cornerRadius: 14, showGradientBorder: false)
    }
    .padding()
}
