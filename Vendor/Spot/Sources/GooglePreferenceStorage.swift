import Foundation
import Combine

protocol SharedInstance: ObservableObject { static var sharedInstance: Self { get } }

@propertyWrapper final class SyncStorage<Value: Codable & Equatable, Key: RawRepresentable> {
    private let key: String
    private let defaults: UserDefaults
    private let owner: any SharedInstance.Type
    private var value: Value
    init(key: Key, defaultValue: Value, on owner: any SharedInstance.Type, ud: UserDefaults) {
        self.key = String(describing: key.rawValue); self.defaults = ud; self.owner = owner
        if let data = ud.data(forKey: self.key), let decoded = try? JSONDecoder().decode(Value.self, from: data) {
            value = decoded
        } else if let existing = ud.object(forKey: self.key) as? Value { value = existing }
        else { value = defaultValue }
    }
    var wrappedValue: Value {
        get { value }
        set {
            guard value != newValue else { return }
            (owner.sharedInstance.objectWillChange as? ObservableObjectPublisher)?.send()
            value = newValue
            if let bool = newValue as? Bool { defaults.set(bool, forKey: key) }
            else if let int = newValue as? Int { defaults.set(int, forKey: key) }
            else if let data = try? JSONEncoder().encode(newValue) { defaults.set(data, forKey: key) }
        }
    }
}

