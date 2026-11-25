import Foundation

// Changes not yet confirmed by the server. Retried on launch, foreground and every change.
struct Pending: Codable {
    var posts: [Serving] = []
    var deletes: [UUID] = []
}

@MainActor
final class History: ObservableObject {
    @Published private(set) var servings: [Serving] = Store.load("servings.json") ?? []
    @Published private(set) var favorites: Set<String> = Store.load("favorites.json") ?? []
    private var pending: Pending = Store.load("pending.json") ?? Pending()
    private var syncing = false

    func caffeine(on day: Date) -> Int { on(day).reduce(0) { $0 + $1.caffeine } }
    var caffeine: Int { caffeine(on: .now) }
    var calories: Int { on(.now).reduce(0) { $0 + $1.calories } }

    func on(_ day: Date) -> [Serving] {
        servings.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }
    }

    func add(_ s: Serving) {
        servings.insert(s, at: 0)
        pending.posts.append(s)
        changed()
    }

    func update(_ s: Serving) {
        guard let i = servings.firstIndex(where: { $0.id == s.id }) else { return }
        servings[i] = s
        pending.posts.removeAll { $0.id == s.id }
        pending.posts.append(s) // server upserts by id
        changed()
    }

    func repeatServing(_ s: Serving) {
        var copy = s
        copy.id = UUID()
        copy.date = Date()
        add(copy)
    }

    func delete(_ s: Serving) {
        servings.removeAll { $0.id == s.id }
        let neverSent = pending.posts.contains { $0.id == s.id }
        pending.posts.removeAll { $0.id == s.id }
        if !neverSent { pending.deletes.append(s.id) }
        changed()
    }

    func toggleFavorite(_ name: String) {
        if !favorites.insert(name).inserted { favorites.remove(name) }
        Store.save(favorites, "favorites.json")
    }

    func sync() {
        guard !syncing else { return }
        syncing = true
        // ponytail: stops at first failure, so one permanently rejected item blocks the queue. Add skip/backoff if the API can reject.
        Task {
            while let s = pending.posts.first {
                do { try await API.log(s) } catch { break }
                if let i = pending.posts.firstIndex(of: s) { pending.posts.remove(at: i) }
            }
            while let id = pending.deletes.first {
                do { try await API.remove(id) } catch { break }
                pending.deletes.removeAll { $0 == id }
            }
            Store.save(pending, "pending.json")
            syncing = false
        }
    }

    private func changed() {
        Store.save(servings, "servings.json")
        Store.save(pending, "pending.json")
        sync()
    }
}
