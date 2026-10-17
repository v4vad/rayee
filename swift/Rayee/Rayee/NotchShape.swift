//
//  NotchShape.swift
//  Rayee
//
//  The recorder's black shape. On a notched screen: a notch-wide band inside the menu bar,
//  joined by small inward curves to a wider body below it. Elsewhere: a rounded capsule.
//

import SwiftUI

struct NotchShape: Shape {
    /// Width and height of the part inside the menu bar; 0 for the capsule
    var bandWidth: CGFloat
    var bandHeight: CGFloat
    var bottomRadius: CGFloat
    /// The body's outer top corners (the capsule uses bottomRadius for all four)
    var topRadius: CGFloat
    var joinRadius: CGFloat = NotchGeometry.joinRadius

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(bottomRadius, topRadius) }
        set {
            bottomRadius = newValue.first
            topRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let bodyTop = rect.minY + bandHeight
        let bodyHeight = rect.maxY - bodyTop
        var path = Path()

        guard bandWidth > 0 else {
            // Capsule
            let radius = min(bottomRadius, rect.height / 2)
            path.addRoundedRect(in: rect, cornerSize: CGSize(width: radius, height: radius), style: .continuous)
            return path
        }
        guard bodyHeight > 0 else {
            path.addRect(CGRect(x: rect.midX - bandWidth / 2, y: rect.minY, width: bandWidth, height: bandHeight))
            return path
        }

        let bottom = min(bottomRadius, bodyHeight / 2, rect.width / 2)
        let top = min(topRadius, bodyHeight / 2)
        let bandLeft = rect.midX - bandWidth / 2
        let bandRight = rect.midX + bandWidth / 2
        let join = max(0, min(joinRadius, bandHeight, (rect.width - bandWidth) / 2 - top))

        path.move(to: CGPoint(x: bandLeft, y: rect.minY))
        path.addLine(to: CGPoint(x: bandRight, y: rect.minY))
        path.addLine(to: CGPoint(x: bandRight, y: bodyTop - join))
        path.addQuadCurve(to: CGPoint(x: bandRight + join, y: bodyTop), control: CGPoint(x: bandRight, y: bodyTop))
        path.addLine(to: CGPoint(x: rect.maxX - top, y: bodyTop))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: bodyTop + top), control: CGPoint(x: rect.maxX, y: bodyTop))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottom))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - bottom, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + bottom, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - bottom), control: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: bodyTop + top))
        path.addQuadCurve(to: CGPoint(x: rect.minX + top, y: bodyTop), control: CGPoint(x: rect.minX, y: bodyTop))
        path.addLine(to: CGPoint(x: bandLeft - join, y: bodyTop))
        path.addQuadCurve(to: CGPoint(x: bandLeft, y: bodyTop - join), control: CGPoint(x: bandLeft, y: bodyTop))
        path.closeSubpath()
        return path
    }
}
