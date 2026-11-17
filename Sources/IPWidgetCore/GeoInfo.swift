import Foundation

/// Geographic information returned by 2ip.io for a specific external IPv4 address.
public struct GeoInfo: Equatable, Sendable {
    public let ip: IPv4Address
    public let countryCode: String?
    public let countryName: String?

    public init(ip: IPv4Address, countryCode: String? = nil, countryName: String? = nil) {
        self.ip = ip
        self.countryCode = Country.normalizedISOCode(countryCode)
        let trimmedName = countryName?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.countryName = (trimmedName?.isEmpty == false) ? trimmedName : nil
    }

    public var flag: String {
        Country.flagEmoji(forISOCode: countryCode)
    }

    /// The name in the user's language, falling back to the English name from the API.
    public func localizedCountryName(locale: Locale = .current) -> String {
        Country.localizedName(forISOCode: countryCode, locale: locale)
            ?? countryName
            ?? "—"
    }
}
