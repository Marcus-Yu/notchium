import CoreGraphics

/// Gesture decisions are independent of rendering, clocks, and feature controls.
enum NotificationDismissGesturePolicy {
    static func isUpward(_ translation: CGSize) -> Bool {
        translation.height < 0 && -translation.height > abs(translation.width) * 1.25
    }

    static func shouldDismiss(translation: CGSize, predicted: CGSize) -> Bool {
        guard isUpward(translation) else { return false }
        return translation.height <= -32
            || (translation.height <= -14 && predicted.height <= -56
                && predicted.height < translation.height && isUpward(predicted))
    }

    static func offset(for translation: CGSize, reduceMotion: Bool) -> CGFloat {
        guard !reduceMotion, isUpward(translation) else { return 0 }
        let distance = -translation.height
        return -(18 * distance / (distance + 32))
    }

    static func opacity(for translation: CGSize) -> Double {
        guard isUpward(translation) else { return 1 }
        return 1 - Double(min(1, max(0, -translation.height - 14) / 32)) * 0.12
    }
}

struct PageSwipeSession {
    private enum Axis { case undecided, horizontal, rejected }
    private var axis = Axis.undecided
    private var x: CGFloat = 0
    private var y: CGFloat = 0
    private var switched = false
    private var active = false

    mutating func begin() { self = Self(); active = true }
    mutating func cancel() { self = Self() }

    /// One physical scroll sequence yields at most one page, without wrapping.
    mutating func update(x deltaX: CGFloat, y deltaY: CGFloat) -> Bool? {
        guard active, !switched, axis != .rejected else { return nil }
        x += deltaX
        y += deltaY
        if axis == .undecided, max(abs(x), abs(y)) >= 8 {
            axis = abs(x) > abs(y) * 1.5 ? .horizontal : .rejected
        }
        guard axis == .horizontal, abs(x) >= 30 else { return nil }
        switched = true
        return x < 0
    }
}
