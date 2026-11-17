import Foundation

public enum IPProvider: String, CaseIterable, Sendable {
    case twoIP
    case icanhazip

    public static let preferenceKey = "preferredIPProvider"
    public static var saved: IPProvider {
        UserDefaults.standard.string(forKey: preferenceKey).flatMap(IPProvider.init(rawValue:)) ?? .twoIP
    }
    public var title: String { self == .twoIP ? "2ip.io" : "icanhazip.com" }
    public var endpoint: URL {
        URL(string: self == .twoIP ? "https://api.2ip.io/" : "https://ipv4.icanhazip.com/")!
    }
}
