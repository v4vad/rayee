//
//  NotchGeometry.swift
//  Rayee
//
//  Where the recorder sits and how big it is: grown out of the notch on screens that have one,
//  or a capsule floating under the menu bar. Pure functions, so they can be tested.
//  Notch detection follows DynamicNotchKit (MIT, github.com/MrKai77/DynamicNotchKit).
//

import AppKit

/// The user's choice in Settings → General.
enum RecorderStyle: String, CaseIterable, Identifiable {
    case automatic
    case floating

    var id: String { rawValue }

    var label: String {
        switch self {
        case .automatic: return "Notch when available"
        case .floating: return "Floating capsule"
        }
    }
}

/// How the recorder is drawn on one screen.
enum RecorderLayoutMode: Equatable {
    /// Grows out of a hardware notch of this size.
    case notch(width: CGFloat, height: CGFloat)
    /// Floats this far below the top of the screen.
    case capsule(gap: CGFloat)
}

/// The parts of an NSScreen the layout needs, as plain values.
struct ScreenInfo: Equatable {
    var frame: CGRect
    var visibleFrame: CGRect
    var safeAreaTop: CGFloat
    var leftAreaWidth: CGFloat?
    var rightAreaWidth: CGFloat?

    init(frame: CGRect, visibleFrame: CGRect, safeAreaTop: CGFloat,
         leftAreaWidth: CGFloat?, rightAreaWidth: CGFloat?) {
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.safeAreaTop = safeAreaTop
        self.leftAreaWidth = leftAreaWidth
        self.rightAreaWidth = rightAreaWidth
    }

    init(_ screen: NSScreen) {
        self.init(
            frame: screen.frame,
            visibleFrame: screen.visibleFrame,
            safeAreaTop: screen.safeAreaInsets.top,
            leftAreaWidth: screen.auxiliaryTopLeftArea?.width,
            rightAreaWidth: screen.auxiliaryTopRightArea?.width)
    }
}

enum NotchGeometry {
    /// Width of the recorder below the menu bar
    static let bodyWidth: CGFloat = 300
    /// Space between the menu bar and the floating capsule
    static let capsuleGap: CGFloat = 6
    /// Transparent room around the shape for the capsule's shadow
    static let shadowMargin: CGFloat = 20
    /// Radius of the curve where the body meets the notch
    static let joinRadius: CGFloat = 12
    /// Used when the menu bar is hidden and can't be measured
    static let fallbackMenuBarHeight: CGFloat = 24

    /// The hardware notch's size, or nil when the screen has none.
    /// macOS reports the usable menu-bar areas left and right of the notch; the notch is what's between.
    static func notchSize(_ screen: ScreenInfo) -> CGSize? {
        guard let left = screen.leftAreaWidth, let right = screen.rightAreaWidth,
              screen.safeAreaTop > 0 else { return nil }
        let width = screen.frame.width - left - right
        guard width > 0 else { return nil }
        return CGSize(width: width, height: screen.safeAreaTop)
    }

    static func menuBarHeight(_ screen: ScreenInfo) -> CGFloat {
        let measured = screen.frame.maxY - screen.visibleFrame.maxY
        if measured > 0 { return measured }
        return max(screen.safeAreaTop, fallbackMenuBarHeight)
    }

    static func mode(for screen: ScreenInfo, style: RecorderStyle) -> RecorderLayoutMode {
        if style == .automatic, let notch = notchSize(screen) {
            return .notch(width: notch.width, height: notch.height)
        }
        return .capsule(gap: menuBarHeight(screen) + capsuleGap)
    }

    static func shapeWidth(_ mode: RecorderLayoutMode) -> CGFloat {
        switch mode {
        case .notch(let width, _): return max(bodyWidth, width)
        case .capsule: return bodyWidth
        }
    }

    /// Height of the part that sits inside the menu bar (none for the capsule).
    static func bandHeight(_ mode: RecorderLayoutMode) -> CGFloat {
        switch mode {
        case .notch(_, let height): return height
        case .capsule: return 0
        }
    }

    /// The shape's bounding box on screen (global coordinates, y up).
    static func shapeFrame(screen: CGRect, mode: RecorderLayoutMode, bodyHeight: CGFloat) -> CGRect {
        let width = shapeWidth(mode)
        let height = bandHeight(mode) + bodyHeight
        let top: CGFloat
        switch mode {
        case .notch: top = screen.maxY
        case .capsule(let gap): top = screen.maxY - gap
        }
        return CGRect(x: screen.midX - width / 2, y: top - height, width: width, height: height)
    }

    /// The areas that take clicks: the notch-wide band and the body below the menu bar.
    /// The bounding box is wider than the notch, so using it would block menu-bar icons.
    static func hitRects(screen: CGRect, mode: RecorderLayoutMode, bodyHeight: CGFloat) -> [CGRect] {
        guard bodyHeight > 0 else { return [] }
        let frame = shapeFrame(screen: screen, mode: mode, bodyHeight: bodyHeight)
        switch mode {
        case .capsule:
            return [frame]
        case .notch(let width, let height):
            let band = CGRect(x: screen.midX - width / 2, y: screen.maxY - height, width: width, height: height)
            let body = CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: bodyHeight)
            return [band, body]
        }
    }

    /// The panel: room for the tallest state, plus shadow room at the sides and bottom.
    static func windowFrame(screen: CGRect, mode: RecorderLayoutMode, maxBodyHeight: CGFloat) -> CGRect {
        let shape = shapeFrame(screen: screen, mode: mode, bodyHeight: maxBodyHeight)
        return CGRect(
            x: shape.minX - shadowMargin,
            y: shape.minY - shadowMargin,
            width: shape.width + 2 * shadowMargin,
            height: shape.height + shadowMargin)
    }

    /// Like CGRect.contains, but a point on the top or right edge counts as inside.
    static func contains(_ rect: CGRect, _ point: CGPoint) -> Bool {
        point.x >= rect.minX && point.x <= rect.maxX && point.y >= rect.minY && point.y <= rect.maxY
    }

    /// The screen to show the recorder on: the one with the pointer, else the main screen, else the first.
    static func screenIndex(mouse: CGPoint, frames: [CGRect], mainIndex: Int?) -> Int? {
        if let index = frames.firstIndex(where: { contains($0, mouse) }) { return index }
        if let mainIndex, frames.indices.contains(mainIndex) { return mainIndex }
        return frames.isEmpty ? nil : 0
    }

    static func currentScreen() -> NSScreen? {
        let screens = NSScreen.screens
        let mainIndex = NSScreen.main.flatMap { main in screens.firstIndex(of: main) }
        guard let index = screenIndex(
            mouse: NSEvent.mouseLocation, frames: screens.map(\.frame), mainIndex: mainIndex) else { return nil }
        return screens[index]
    }
}
