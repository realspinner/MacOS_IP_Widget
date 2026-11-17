import Darwin
import Foundation

/// One checked result shared by the companion and the read-only widget.
public struct SharedWidgetSnapshot: Codable, Equatable, Sendable {
    public static let maximumAge: TimeInterval = 300
    public let version: Int
    public let checkedAt: Date
    public let lastUpdated: Date?
    public let status: WidgetStatus
    public let interfaceName: String?
    public let rating: IPRating?

    public init(checkedAt: Date, lastUpdated: Date?, status: WidgetStatus, interfaceName: String?, rating: IPRating? = nil) {
        version = 1
        self.checkedAt = checkedAt
        self.lastUpdated = lastUpdated
        self.status = status
        self.interfaceName = interfaceName
        self.rating = rating
    }

    public var expiresAt: Date { checkedAt.addingTimeInterval(Self.maximumAge) }

    public func displayStatus(at now: Date) -> WidgetStatus {
        guard version == 1, checkedAt <= now.addingTimeInterval(5), now <= expiresAt else {
            return .unavailable(.appNotRunning)
        }
        if case .online(let geo) = status, !geo.ip.isPublic { return .unavailable(.appNotRunning) }
        return status
    }
}

/// Uses a narrowly scoped read-only sandbox exception in the extension.
public struct SharedWidgetStore: Sendable {
    public let url: URL

    public init(url: URL) { self.url = url }

    public static func standard() throws -> SharedWidgetStore {
        // Foundation home-directory APIs may return the extension's container.
        // Resolve the account home consistently in both processes instead.
        var account = passwd()
        var result: UnsafeMutablePointer<passwd>?
        var buffer = [CChar](repeating: 0, count: 16384)
        let home: String = try buffer.withUnsafeMutableBufferPointer { bytes in
            let code = getpwuid_r(getuid(), &account, bytes.baseAddress, bytes.count, &result)
            guard code == 0, result != nil, let directory = account.pw_dir else {
                throw CocoaError(.fileReadNoPermission)
            }
            return String(cString: directory)
        }
        return SharedWidgetStore(url: URL(fileURLWithPath: home, isDirectory: true)
            .appendingPathComponent("Library/Application Support/IPWidget/widget-state.json"))
    }

    public func write(_ snapshot: SharedWidgetSnapshot) throws {
        let manager = FileManager.default
        let directory = url.deletingLastPathComponent()
        try manager.createDirectory(at: directory, withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: url, options: .atomic)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public func read() throws -> SharedWidgetSnapshot {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= 16384 else { throw CocoaError(.fileReadCorruptFile) }
        let data = try Data(contentsOf: url)
        guard data.count <= 16384 else { throw CocoaError(.fileReadCorruptFile) }
        return try JSONDecoder().decode(SharedWidgetSnapshot.self, from: data)
    }
}
