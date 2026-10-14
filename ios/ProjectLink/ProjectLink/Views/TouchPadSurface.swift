import SwiftUI
import UIKit

/// Raw multi-touch pad — responds on touchesBegan (no drag-hold delay).
/// 1 finger move · tap = left click · 2 fingers tap = right click · 2 finger vertical = scroll
struct TouchPadSurface: UIViewRepresentable {
    var onMove: (_ dx: CGFloat, _ dy: CGFloat) -> Void
    var onLeftClick: () -> Void
    var onRightClick: () -> Void
    var onScroll: (_ delta: Int16) -> Void

    func makeUIView(context: Context) -> TouchPadUIView {
        let v = TouchPadUIView()
        v.onMove = onMove
        v.onLeftClick = onLeftClick
        v.onRightClick = onRightClick
        v.onScroll = onScroll
        v.isMultipleTouchEnabled = true
        v.backgroundColor = .clear
        return v
    }

    func updateUIView(_ uiView: TouchPadUIView, context: Context) {
        uiView.onMove = onMove
        uiView.onLeftClick = onLeftClick
        uiView.onRightClick = onRightClick
        uiView.onScroll = onScroll
    }
}

final class TouchPadUIView: UIView {
    var onMove: ((_ dx: CGFloat, _ dy: CGFloat) -> Void)?
    var onLeftClick: (() -> Void)?
    var onRightClick: (() -> Void)?
    var onScroll: ((_ delta: Int16) -> Void)?

    private var lastPoints: [ObjectIdentifier: CGPoint] = [:]
    private var touchStart: Date?
    private var maxTouches = 0
    private var totalTravel: CGFloat = 0
    private var lastScrollY: CGFloat?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if touchStart == nil {
            touchStart = Date()
            totalTravel = 0
            maxTouches = 0
            lastScrollY = nil
        }
        maxTouches = max(maxTouches, event?.allTouches?.filter { $0.phase != .cancelled && $0.phase != .ended }.count ?? touches.count)
        for t in touches {
            lastPoints[ObjectIdentifier(t)] = t.location(in: self)
        }
        if maxTouches >= 2, let t = touches.first {
            lastScrollY = t.location(in: self).y
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        let active = event?.allTouches?.filter { $0.phase == .began || $0.phase == .moved || $0.phase == .stationary } ?? []
        maxTouches = max(maxTouches, active.count)

        if active.count >= 2 {
            // Two-finger scroll (average Y)
            let y = active.map { $0.location(in: self).y }.reduce(0, +) / CGFloat(active.count)
            if let prev = lastScrollY {
                let dy = y - prev
                if abs(dy) >= 4 {
                    let ticks = Int16(clamping: Int((-dy / 10).rounded()))
                    if ticks != 0 { onScroll?(ticks) }
                    lastScrollY = y
                }
            } else {
                lastScrollY = y
            }
            // Still allow coarse move with average of first finger if desired — skip move while scrolling
            for t in touches {
                lastPoints[ObjectIdentifier(t)] = t.location(in: self)
            }
            return
        }

        // Single finger — immediate relative move
        for t in touches {
            let id = ObjectIdentifier(t)
            let now = t.location(in: self)
            if let prev = lastPoints[id] {
                let dx = now.x - prev.x
                let dy = now.y - prev.y
                totalTravel += hypot(dx, dy)
                if dx != 0 || dy != 0 {
                    onMove?(dx, dy)
                }
            }
            lastPoints[id] = now
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches { lastPoints.removeValue(forKey: ObjectIdentifier(t)) }
        let remaining = event?.allTouches?.filter { $0.phase != .ended && $0.phase != .cancelled && !touches.contains($0) } ?? []
        if remaining.isEmpty {
            finishGesture()
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches { lastPoints.removeValue(forKey: ObjectIdentifier(t)) }
        let remaining = event?.allTouches?.filter { $0.phase != .ended && $0.phase != .cancelled && !touches.contains($0) } ?? []
        if remaining.isEmpty {
            touchStart = nil
            maxTouches = 0
            totalTravel = 0
            lastScrollY = nil
            lastPoints.removeAll()
        }
    }

    private func finishGesture() {
        let duration = Date().timeIntervalSince(touchStart ?? Date())
        let wasTap = totalTravel < 8 && duration < 0.35
        if wasTap {
            if maxTouches >= 2 {
                onRightClick?()
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            } else {
                onLeftClick?()
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }
        touchStart = nil
        maxTouches = 0
        totalTravel = 0
        lastScrollY = nil
        lastPoints.removeAll()
    }
}
