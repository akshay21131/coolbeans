import Foundation

@MainActor
final class Menu: ObservableObject {
    @Published var data: MenuData? = Store.load("menu.json") // cached copy works offline
    @Published var loading = false
    @Published var error: String?

    func load() async {
        loading = true
        error = nil
        do {
            let fresh = try await API.menu()
            data = fresh
            Store.save(fresh, "menu.json")
        } catch {
            if data == nil { self.error = error.localizedDescription } // cache exists: stay quiet
        }
        loading = false
    }
}
