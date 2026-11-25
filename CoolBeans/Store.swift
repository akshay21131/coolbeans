import Foundation

// JSON files in the Documents directory.
enum Store {
    static func load<T: Decodable>(_ name: String) -> T? {
        try? JSONDecoder().decode(T.self, from: Data(contentsOf: .documentsDirectory.appending(path: name)))
    }

    static func save<T: Encodable>(_ value: T, _ name: String) {
        try? JSONEncoder().encode(value).write(to: .documentsDirectory.appending(path: name))
    }
}
