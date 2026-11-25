import Foundation

enum API {
    static let base = URL(string: "http://localhost:8000")! // mock_server.py

    static func menu() async throws -> MenuData {
        async let drinks: [Drink] = get("drinks")
        async let milks: [Option] = get("milks")
        async let syrups: [Option] = get("syrups")
        return try await MenuData(drinks: drinks, milks: milks, syrups: syrups)
    }

    static func get<T: Decodable>(_ path: String) async throws -> T {
        let (data, response) = try await URLSession.shared.data(from: base.appending(path: path))
        try check(response)
        return try JSONDecoder().decode(T.self, from: data)
    }

    static func log(_ s: Serving) async throws {
        var req = URLRequest(url: base.appending(path: "servings"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(s)
        try check(try await URLSession.shared.data(for: req).1)
    }

    static func remove(_ id: UUID) async throws {
        var req = URLRequest(url: base.appending(path: "servings/\(id.uuidString)"))
        req.httpMethod = "DELETE"
        try check(try await URLSession.shared.data(for: req).1)
    }

    static func check(_ response: URLResponse) throws {
        guard (response as? HTTPURLResponse)?.statusCode ?? 0 < 300 else { throw URLError(.badServerResponse) }
    }
}
