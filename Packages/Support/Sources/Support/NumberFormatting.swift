import Foundation

public enum CompactNumberFormatting {
    public static func fullString(_ value: Int) -> String {
        value.formatted()
    }

    public static func approximateInYi(_ value: Int) -> String? {
        let absolute = abs(value)
        guard absolute >= 10_000_000 else { return nil }
        let yi = Double(value) / 100_000_000
        let formatted = abs(yi) >= 1 ? String(format: "%.1f", yi) : String(format: "%.2f", yi)
        return "约 \(formatted) 亿"
    }
}
