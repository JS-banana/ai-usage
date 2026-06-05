import AppKit

struct QuotaMenuBarImageRenderer {
    func image(for state: QuotaMenuBarGlyphState) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        NSColor.clear.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

        switch state {
        case .dualWindows(let leftRatio, let rightRatio, let isDimmed):
            drawTank(x: 3, width: 5, fillRatio: leftRatio, dimmed: isDimmed, canvasSize: size)
            drawTank(x: 10, width: 5, fillRatio: rightRatio, dimmed: isDimmed, canvasSize: size)
        case .singlePlan(let ratio, let isDimmed):
            drawTank(x: 5, width: 8, fillRatio: ratio, dimmed: isDimmed, canvasSize: size)
        case .empty(let kind):
            switch kind {
            case .dual:
                drawTank(x: 3, width: 5, fillRatio: 0.18, dimmed: true, canvasSize: size)
                drawTank(x: 10, width: 5, fillRatio: 0.18, dimmed: true, canvasSize: size)
            case .single:
                drawTank(x: 5, width: 8, fillRatio: 0.18, dimmed: true, canvasSize: size)
            }
        }

        image.isTemplate = true
        return image
    }

    private func drawTank(
        x: CGFloat,
        width: CGFloat,
        fillRatio: Double,
        dimmed: Bool,
        canvasSize: NSSize
    ) {
        let trackRect = NSRect(
            x: x,
            y: 2,
            width: width,
            height: canvasSize.height - 4
        )
        drawTrack(in: trackRect, dimmed: dimmed)
        drawFill(in: fillRect(in: trackRect, fillRatio: fillRatio), dimmed: dimmed)
    }

    private func fillRect(
        in trackRect: NSRect,
        fillRatio: Double
    ) -> NSRect {
        let trackHeight = trackRect.height
        let clamped = max(0.16, min(fillRatio, 1))
        let missingHeight = trackHeight * (1 - clamped)
        let visibleMissingHeight = clamped >= 0.995 ? 0 : max(missingHeight, 3.2)
        let filledHeight = max(trackHeight - visibleMissingHeight, 2)
        return NSRect(
            x: trackRect.minX,
            y: trackRect.minY,
            width: trackRect.width,
            height: filledHeight
        )
    }

    private func drawTrack(in rect: NSRect, dimmed: Bool) {
        drawRoundedRect(in: rect, alpha: trackAlpha(dimmed: dimmed))
    }

    private func drawFill(in rect: NSRect, dimmed: Bool) {
        drawRoundedRect(in: rect, alpha: fillAlpha(dimmed: dimmed))
    }

    private func drawRoundedRect(in rect: NSRect, alpha: CGFloat) {
        let path = NSBezierPath(roundedRect: rect, xRadius: 1.6, yRadius: 1.6)
        NSColor.labelColor.withAlphaComponent(alpha).setFill()
        path.fill()
    }

    private func trackAlpha(dimmed: Bool) -> CGFloat {
        dimmed ? 0.20 : 0.32
    }

    private func fillAlpha(dimmed: Bool) -> CGFloat {
        dimmed ? 0.55 : 1
    }
}
