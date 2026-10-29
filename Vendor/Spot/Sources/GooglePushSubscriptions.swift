import Foundation

// Owned by the push queue. Connection resets must retain unsent requests, while
// completed/expired subscriptions must never issue an action on a later login.
struct GooglePushSubscriptions<Message> {
    struct Subscription {
        let id: UUID
        var whenReady: (() -> Void)?
        let receive: (Message?) -> Bool
    }
    private(set) var subscriptions: [Subscription] = []
    var isEmpty: Bool { subscriptions.isEmpty }

    mutating func insert(whenReady: @escaping () -> Void, receive: @escaping (Message?) -> Bool) -> UUID {
        let id = UUID()
        subscriptions.append(Subscription(id: id, whenReady: whenReady, receive: receive))
        return id
    }
    mutating func takeReadyCallbacks() -> [() -> Void] {
        let callbacks = subscriptions.compactMap(\.whenReady)
        for index in subscriptions.indices { subscriptions[index].whenReady = nil }
        return callbacks
    }
    @discardableResult mutating func remove(_ id: UUID) -> Subscription? {
        guard let index = subscriptions.firstIndex(where: { $0.id == id }) else { return nil }
        return subscriptions.remove(at: index)
    }
    mutating func removeAll() -> [Subscription] {
        let removed = subscriptions
        subscriptions.removeAll()
        return removed
    }
}
