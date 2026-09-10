import CoreGraphics
import Foundation

/// A candidate focused window, in AppKit (bottom-left origin) coordinates.
public struct WindowCandidate: Equatable, Sendable {
    /// Front-to-back position in the window list; lower is nearer the front.
    public let order: Int
    public let frame: CGRect

    public init(order: Int, frame: CGRect) {
        self.order = order
        self.frame = frame
    }

    public var area: CGFloat { frame.width * frame.height }
}

public enum WindowSelection {
    /// The smallest window either dimension may have before it is ignored.
    public static let minimumSide: CGFloat = 60

    /// Read one `CGWindowListCopyWindowInfo` entry, in Quartz coordinates.
    ///
    /// Returns nil for anything that is not a plain, visible, big-enough
    /// window belonging to `pid`.
    public static func quartzFrame(from item: [String: Any], pid: pid_t) -> CGRect? {
        guard (item[kCGWindowOwnerPID as String] as? pid_t) == pid,
              (item[kCGWindowLayer as String] as? Int) == 0,
              (item[kCGWindowAlpha as String] as? CGFloat ?? 1) > 0,
              let bounds = item[kCGWindowBounds as String] as? [String: Any],
              let x = bounds["X"] as? CGFloat, let y = bounds["Y"] as? CGFloat,
              let width = bounds["Width"] as? CGFloat, let height = bounds["Height"] as? CGFloat,
              width > minimumSide, height > minimumSide else { return nil }
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// Pick the window to draw around.
    ///
    /// `CGWindowList` is ordered front-to-back, so the first candidate is
    /// normally the focused window. That is not what we want here: browser
    /// pop-outs, find panels, and permission sheets can temporarily be first
    /// even though the user's main window is the useful focus target. Pick the
    /// largest window and use front-to-back order only to break ties.
    public static func primary(among candidates: [WindowCandidate]) -> WindowCandidate? {
        var best: WindowCandidate?
        for candidate in candidates {
            guard let current = best else {
                best = candidate
                continue
            }
            if beats(candidate, current) { best = candidate }
        }
        return best
    }

    /// Whether `candidate` is a better focus target than `current`: bigger
    /// wins, and on a tie the one nearer the front wins.
    static func beats(_ candidate: WindowCandidate, _ current: WindowCandidate) -> Bool {
        // One comparison over both keys. The orders are deliberately swapped:
        // a larger area wins, and on a tie a *lower* order, meaning nearer the
        // front, wins.
        (candidate.area, current.order) > (current.area, candidate.order)
    }

    /// Convert Quartz window bounds to AppKit coordinates.
    ///
    /// Quartz uses a top-left origin; AppKit uses a bottom-left origin. The
    /// reference line is the main display's global top edge, not an arbitrary
    /// entry in the screen list, which matters when a second display sits
    /// above or below the main one.
    public static func cocoaRect(_ rect: CGRect, mainTop: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: mainTop - rect.maxY, width: rect.width, height: rect.height)
    }

    /// The tolerance, in points, for treating a window as filling a display.
    public static let fullscreenTolerance: CGFloat = 8

    public static func isFullscreen(_ rect: CGRect, screens: [CGRect]) -> Bool {
        screens.contains { screen in
            screen.intersection(rect).height >= screen.height - fullscreenTolerance
                && rect.minY <= screen.minY + fullscreenTolerance
        }
    }

    /// The screens the ring light should cover.
    ///
    /// `.focused` falls back to the main screen when no focused window frame
    /// is known, so selecting it never leaves the light off entirely.
    public static func screenIndices(for choice: DisplayChoice,
                                     screens: [CGRect],
                                     mainIndex: Int?,
                                     focusedFrame: CGRect?) -> [Int] {
        switch choice {
        case .all:
            return Array(screens.indices)
        case .main:
            return mainIndex.map { [$0] } ?? []
        case .focused:
            guard let focusedFrame else { return mainIndex.map { [$0] } ?? [] }
            return screens.indices.filter { screens[$0].intersects(focusedFrame) }
        }
    }
}
