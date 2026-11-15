import Foundation

// Allowance amounts are stored as whole numbers in the smallest unit of the
// family's currency (cents, pence...), so they never pick up rounding errors.

enum Money {
    private static var formatters: [String: NumberFormatter] = [:]

    private static func formatter(_ currency: String) -> NumberFormatter {
        if let hit = formatters[currency] { return hit }
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currency
        formatters[currency] = f
        return f
    }

    /// How many of the smallest unit make one whole (100 for dollars, 1 for yen).
    static func scale(_ currency: String) -> Int {
        let digits = formatter(currency).maximumFractionDigits
        return Int(pow(10, Double(max(0, min(3, digits)))))
    }

    /// "$1.50" for 150 US cents.
    static func format(_ amount: Int, _ currency: String) -> String {
        let value = Double(amount) / Double(scale(currency))
        return formatter(currency).string(from: NSNumber(value: value)) ?? "\(value)"
    }

    /// Reads what a parent typed ("1.50", "1,50", "$2") into the smallest unit. Nil if it isn't a number.
    static func parse(_ text: String, _ currency: String) -> Int? {
        let cleaned = text
            .replacingOccurrences(of: ",", with: ".")
            .filter { $0.isNumber || $0 == "." }
        guard !cleaned.isEmpty, let value = Double(cleaned), value >= 0 else { return nil }
        return Int((value * Double(scale(currency))).rounded())
    }

    /// The amount as plain digits for an edit box ("1.50").
    static func plain(_ amount: Int, _ currency: String) -> String {
        let scale = scale(currency)
        if scale == 1 { return "\(amount)" }
        let places = scale == 1000 ? 3 : scale == 10 ? 1 : 2
        return String(format: "%.\(places)f", Double(amount) / Double(scale))
    }

    /// The phone's own currency, for a new family.
    static var local: String {
        Locale.current.currency?.identifier ?? "USD"
    }
}
