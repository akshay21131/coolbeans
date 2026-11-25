import Foundation

struct Drink: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let caffeine: Int   // mg, medium size
    let calories: Int   // medium size
}

// Used for both milk and syrup.
struct Option: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let calories: Int
}

struct MenuData: Codable {
    let drinks: [Drink]
    let milks: [Option]
    let syrups: [Option]
}

enum Size: String, Codable, CaseIterable {
    case small, medium, large
    var scale: Double { self == .small ? 0.75 : self == .medium ? 1 : 1.25 }
}

struct Serving: Codable, Identifiable, Equatable {
    var id = UUID()
    var date = Date()
    let drink: String
    let size: Size
    let shots: Int
    let decaf: Bool
    let milk: String
    let syrup: String
    let caffeine: Int
    let calories: Int
}
