import Foundation

public enum Country {
    /// Returns a regional-indicator flag emoji for a two-letter ISO country code,
    /// or a globe for anything that cannot be turned into a flag.
    public static func flagEmoji(forISOCode code: String?) -> String {
        guard let code else { return "🌐" }
        let upper = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard upper.count == 2,
              upper != "XX",
              upper.unicodeScalars.allSatisfy({ $0.value >= 65 && $0.value <= 90 })
        else {
            return "🌐"
        }

        var flag = String()
        for scalar in upper.unicodeScalars {
            guard let regionalIndicator = UnicodeScalar(0x1F1E6 + scalar.value - 65) else {
                return "🌐"
            }
            flag.unicodeScalars.append(regionalIndicator)
        }
        return flag
    }

    /// Country name localized using the requested locale.
    public static func localizedName(forISOCode code: String?, locale: Locale = .current) -> String? {
        guard let code else { return nil }
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard normalized.count == 2 else { return nil }
        return locale.localizedString(forRegionCode: normalized)
    }

    public static func normalizedISOCode(_ code: String?) -> String? {
        guard let code else { return nil }
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard normalized.count == 2,
              normalized != "XX",
              normalized.unicodeScalars.allSatisfy({ $0.value >= 65 && $0.value <= 90 })
        else {
            return nil
        }
        return normalized
    }
}
