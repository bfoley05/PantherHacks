//
//  SharedComponents.swift
//  PTApp
//

import SwiftUI
import UIKit

struct StrideProgressRing: View {
    var progress: Double
    var lineWidth: CGFloat = 14

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(uiColor: .tertiarySystemFill), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(min(max(progress, 0), 1)))
                .stroke(
                    AngularGradient(
                        colors: [StrideTheme.accent, StrideTheme.success],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
    }
}

struct StrideLogoView: View {
    var height: CGFloat = 28

    var body: some View {
        Group {
            if let image = loadLogoImage() {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(height: height)
            } else {
                Label {
                    Text("Stride")
                        .font(.headline.weight(.semibold))
                } icon: {
                    Image(systemName: "figure.run")
                        .font(.title3.weight(.semibold))
                }
                .foregroundStyle(StrideTheme.accent)
            }
        }
    }

    private func loadLogoImage() -> UIImage? {
        if let img = UIImage(named: "Stride_Logo") { return img }
        if let url = Bundle.main.url(forResource: "Stride_Logo", withExtension: "png"),
           let data = try? Data(contentsOf: url),
           let img = UIImage(data: data) {
            return img
        }
        return nil
    }
}
