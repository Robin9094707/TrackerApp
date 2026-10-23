//
//  CustomLoadingIndicator.swift
//
//
//  Created by Leon Böttger on 19.12.23.
//

import SwiftUI

public struct LoadingIndicator: View {
    public init(color: Color? = nil) {
        self.color = color
    }

    @State private var rotation: Double = 0
    @Environment(\.colorScheme) private var colorScheme
    var color: Color?

    public var body: some View {
        let max = 50.0
        let color = getColor(isLight: colorScheme.isLight)

        Color.clear
            .frame(maxWidth: max, maxHeight: max)
            .overlay(
                GeometryReader { geo in
                    let min = min(geo.size.width, geo.size.height)
                    let lineWidth = min * 0.21

                    Circle()
                        .trim(from: 0, to: 0.8)
                        .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .rotationEffect(Angle(degrees: 50))
                        .padding(lineWidth / 2)
                        .mask(
                            AngularGradient(
                                colors: [.clear, .black], center: .center, startAngle: Angle(degrees: 60),
                                endAngle: Angle(degrees: 360)
                            )
                        )
                        .rotationEffect(Angle(degrees: -60))
                        .rotationEffect(Angle(degrees: rotation))
                        .animation(
                            Animation.linear(duration: 2).repeatForever(autoreverses: false), value: rotation
                        )
                        .onAppear {
                            runAfter(seconds: 0.01) {
                                rotation = 360
                            }
                        }
                        .foregroundColor(color)
                }
            )
            .aspectRatio(1, contentMode: .fit)
    }

    func getColor(isLight _: Bool) -> Color {
        if let color {
            return color
        }
        return Color.mainColor
    }
}
