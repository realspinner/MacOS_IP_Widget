import Foundation

/// A strict, canonical IPv4 address.
///
/// The textual form is always a dotted quad without leading zeroes, e.g. `45.159.12.7`.
public struct IPv4Address: Codable, Hashable, Sendable, Comparable, CustomStringConvertible {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    /// Parses a dotted-quad string. Surrounding whitespace (including the trailing
    /// newline returned by `https://2ip.io/`) is ignored, leading zeroes are removed,
    /// but anything that is not exactly four decimal octets in `0...255` is rejected.
    public init?(canonicalizing text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }

        var value: UInt32 = 0
        for part in parts {
            guard (1...3).contains(part.count),
                  part.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let octet = UInt16(part),
                  octet <= 255
            else {
                return nil
            }
            value = (value << 8) | UInt32(octet)
        }
        self.rawValue = value
    }

    public var octets: [UInt8] {
        [
            UInt8((rawValue >> 24) & 0xFF),
            UInt8((rawValue >> 16) & 0xFF),
            UInt8((rawValue >> 8) & 0xFF),
            UInt8(rawValue & 0xFF),
        ]
    }

    public var description: String {
        let octets = octets
        return "\(octets[0]).\(octets[1]).\(octets[2]).\(octets[3])"
    }

    public static func < (lhs: IPv4Address, rhs: IPv4Address) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var isLoopback: Bool {
        (rawValue >> 24) == 127
    }

    public var isPrivate: Bool {
        let first = (rawValue >> 24) & 0xFF
        let second = (rawValue >> 16) & 0xFF
        switch (first, second) {
        case (10, _):
            return true
        case (172, 16...31):
            return true
        case (192, 168):
            return true
        default:
            return false
        }
    }

    public var isLinkLocal: Bool {
        ((rawValue >> 16) & 0xFFFF) == 0xA9FE // 169.254.0.0/16
    }

    public var isPublic: Bool {
        !isLoopback && !isPrivate && !isLinkLocal && rawValue != 0 && rawValue != 0xFFFF_FFFF
    }
}
