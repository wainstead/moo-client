import Foundation

public protocol RelayStateStore: AnyObject {
    var sessionID: String { get set }
    var lastOffset: UInt64 { get set }
}

public final class InMemoryRelayStateStore: RelayStateStore {
    public var sessionID: String
    public var lastOffset: UInt64

    public init(sessionID: String = UUID().uuidString, lastOffset: UInt64 = 0) {
        self.sessionID = sessionID
        self.lastOffset = lastOffset
    }
}

public final class UserDefaultsRelayStateStore: RelayStateStore {
    private let defaults: UserDefaults
    private let sessionKey: String
    private let offsetKey: String

    public init(
        defaults: UserDefaults = .standard,
        namespace: String = "moo.relay"
    ) {
        self.defaults = defaults
        self.sessionKey = "\(namespace).sessionID"
        self.offsetKey = "\(namespace).lastOffset"

        if defaults.string(forKey: sessionKey) == nil {
            defaults.set(UUID().uuidString, forKey: sessionKey)
        }
    }

    public var sessionID: String {
        get {
            defaults.string(forKey: sessionKey) ?? UUID().uuidString
        }
        set {
            defaults.set(newValue, forKey: sessionKey)
        }
    }

    public var lastOffset: UInt64 {
        get {
            UInt64(defaults.integer(forKey: offsetKey))
        }
        set {
            defaults.set(Int(newValue), forKey: offsetKey)
        }
    }
}
