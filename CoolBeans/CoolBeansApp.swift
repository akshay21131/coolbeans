import SwiftUI

@main
struct CoolBeansApp: App {
    @StateObject var menu = Menu()
    @StateObject var history = History()
    @Environment(\.scenePhase) var phase

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(menu)
                .environmentObject(history)
                .task { await menu.load() }
                .onChange(of: phase) { if phase == .active { history.sync() } }
        }
    }
}
