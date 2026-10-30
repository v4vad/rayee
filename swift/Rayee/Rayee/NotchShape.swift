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

        // Each corner's curve starts and ends `reach` away from it, clamped so neighbouring curves never overlap
        let side = (rect.width - bandWidth) / 2
        let joinReach = min(join * 1.6, bandHeight, side / 2)
        let topReach = min(top * 1.6, side / 2, bodyHeight / 2)
        let bottomReach = min(bottom * 1.6, bodyHeight / 2, rect.width / 2)

        path.move(to: CGPoint(x: bandLeft, y: rect.minY))
        path.addLine(to: CGPoint(x: bandRight, y: rect.minY))
        Self.smoothCorner(&path, CGPoint(x: bandRight, y: bodyTop), in: CGVector(dx: 0, dy: 1), out: CGVector(dx: 1, dy: 0), reach: joinReach)
        Self.smoothCorner(&path, CGPoint(x: rect.maxX, y: bodyTop), in: CGVector(dx: 1, dy: 0), out: CGVector(dx: 0, dy: 1), reach: topReach)
        Self.smoothCorner(&path, CGPoint(x: rect.maxX, y: rect.maxY), in: CGVector(dx: 0, dy: 1), out: CGVector(dx: -1, dy: 0), reach: bottomReach)
        Self.smoothCorner(&path, CGPoint(x: rect.minX, y: rect.maxY), in: CGVector(dx: -1, dy: 0), out: CGVector(dx: 0, dy: -1), reach: bottomReach)
        Self.smoothCorner(&path, CGPoint(x: rect.minX, y: bodyTop), in: CGVector(dx: 0, dy: -1), out: CGVector(dx: 1, dy: 0), reach: topReach)
        Self.smoothCorner(&path, CGPoint(x: bandLeft, y: bodyTop), in: CGVector(dx: 1, dy: 0), out: CGVector(dx: 0, dy: -1), reach: joinReach)
        path.closeSubpath()
        return path
    }

    // MARK: - Corners

    /// One smoothed ("continuous") corner, like iOS uses. Travels along `incoming` toward `corner` and leaves along `outgoing`.
    /// The curve starts `reach` before the corner and ends `reach` after it; its handles sit close to the corner
    /// (0.22 × reach), which gives the long, gradual ease-in with no kink where a straight edge meets the round.
    private static func smoothCorner(_ path: inout Path, _ corner: CGPoint, in incoming: CGVector, out outgoing: CGVector, reach: CGFloat) {
        guard reach > 0 else {
            path.addLine(to: corner)
            return
        }
        let handle = reach * 0.22
        path.addLine(to: CGPoint(x: corner.x - incoming.dx * reach, y: corner.y - incoming.dy * reach))
        path.addCurve(
            to: CGPoint(x: corner.x + outgoing.dx * reach, y: corner.y + outgoing.dy * reach),
            control1: CGPoint(x: corner.x - incoming.dx * handle, y: corner.y - incoming.dy * handle),
            control2: CGPoint(x: corner.x + outgoing.dx * handle, y: corner.y + outgoing.dy * handle))
    }
}
