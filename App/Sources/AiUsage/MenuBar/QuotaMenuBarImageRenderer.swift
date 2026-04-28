import AppKit

struct QuotaMenuBarImageRenderer {
    func image(for state: QuotaMenuBarGlyphState) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        NSColor.clear.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

        let leftRect = barRect(
            x: 3,
            fillRatio: state.leftRatio,
            canvasSize: size,
            barWidth: 5,
            topInset: 2,
            bottomInset: 2
        )
        let rightRect = barRect(
            x: 10,
            fillRatio: state.rightRatio,
            canvasSize: size,
            barWidth: 5,
            topInset: 2,
            bottomInset: 2
        )

        drawBar(in: leftRect, dimmed: state.isDimmed)
        drawBar(in: rightRect, dimmed: state.isDimmed)

        image.isTemplate = true
        return image
    }

    private func barRect(
        x: CGFloat,
        fillRatio: Double,
        canvasSize: NSSize,
        barWidth: CGFloat,
        topInset: CGFloat,
        bottomInset: CGFloat
    ) -> NSRect {
        let trackHeight = canvasSize.height - topInset - bottomInset
        let clamped = max(0.16, min(fillRatio, 1))
        let filledHeight = max(trackHeight * clamped, 2)
        return NSRect(
            x: x,
            y: bottomInset,
            width: barWidth,
            height: filledHeight
        )
    }

    private func drawBar(in rect: NSRect, dimmed: Bool) {
        let path = NSBezierPath(roundedRect: rect, xRadius: 1.6, yRadius: 1.6)
        let alpha: CGFloat = dimmed ? 0.55 : 1
        NSColor.labelColor.withAlphaComponent(alpha).setFill()
        path.fill()
    }
}
