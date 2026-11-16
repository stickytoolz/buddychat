import Foundation

enum DBError: LocalizedError {
    case denied(String)
    case server(String)
    var errorDescription: String? {
        switch self {
        case .denied(let detail): return "The server said no (permission denied) — \(detail)"
        case .server(let m): return m
        }
    }
}

/// Firebase Realtime Database over plain HTTPS (no SDK needed).
final class Database {
    var tokenProvider: () async -> String? = { nil }

    static let serverTimestamp: [String: Any] = [".sv": "timestamp"]

    private func url(_ path: String, query: [String: String] = [:]) async -> URL {
        var comps = URLComponents(string: FirebaseConfig.databaseURL + "/" + path + ".json")!
        var items = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        if let token = await tokenProvider() { items.append(URLQueryItem(name: "auth", value: token)) }
        comps.queryItems = items
        return comps.url!
    }

    @discardableResult
    private func send(_ method: String, _ path: String, body: Any?, query: [String: String] = [:]) async throws -> Any? {
        var req = URLRequest(url: await url(path, query: query))
        req.httpMethod = method
        if let body {
            req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.fragmentsAllowed])
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        if status == 401 || status == 403 {
            let msg = (obj as? [String: Any])?["error"] as? String ?? "no details"
            let where_ = path.split(separator: "/").first.map(String.init) ?? path
            throw DBError.denied("\(method) \(where_), \(status): \(msg)")
        }
        if status >= 400 {
            let msg = (obj as? [String: Any])?["error"] as? String ?? "Server error \(status)"
            throw DBError.server(msg)
        }
        return obj is NSNull ? nil : obj
    }

    func get(_ path: String, query: [String: String] = [:]) async throws -> Any? {
        try await send("GET", path, body: nil, query: query)
    }
    func put(_ path: String, _ value: Any) async throws { try await send("PUT", path, body: value) }
    func patch(_ path: String, _ value: [String: Any]) async throws { try await send("PATCH", path, body: value) }
    func delete(_ path: String) async throws { try await send("DELETE", path, body: nil) }
    /// Adds a child with an auto-generated, time-ordered key. Returns the key.
    @discardableResult
    func push(_ path: String, _ value: Any) async throws -> String {
        let obj = try await send("POST", path, body: value)
        return (obj as? [String: Any])?["name"] as? String ?? ""
    }

    /// Opens a live stream of changes at `path`. The handler gets the whole current value every time it changes.
    func listen(_ path: String, query: [String: String] = [:], onChange: @escaping @MainActor (Any?) -> Void) -> LiveQuery {
        let q = LiveQuery(db: self, path: path, query: query, onChange: onChange)
        q.start()
        return q
    }

    fileprivate func streamURL(_ path: String, query: [String: String]) async -> URL {
        await url(path, query: query)
    }
}

/// One Server-Sent Events stream from the Realtime Database, kept as a local copy of the data.
final class LiveQuery {
    private weak var db: Database?
    let path: String
    private let query: [String: String]
    private let onChange: @MainActor (Any?) -> Void
    private var task: Task<Void, Never>?
    private var tree: Any? = nil
    private var stopped = false

    fileprivate init(db: Database, path: String, query: [String: String], onChange: @escaping @MainActor (Any?) -> Void) {
        self.db = db
        self.path = path
        self.query = query
        self.onChange = onChange
    }

    func start() {
        task?.cancel()
        stopped = false
        task = Task { [weak self] in await self?.run() }
    }

    func stop() {
        stopped = true
        task?.cancel()
        task = nil
    }

    deinit { task?.cancel() }

    private func run() async {
        var backoff: UInt64 = 1
        while !Task.isCancelled && !stopped {
            guard let db else { return }
            var req = URLRequest(url: await db.streamURL(path, query: query))
            req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            req.timeoutInterval = 90
            do {
                let (bytes, response) = try await URLSession.shared.bytes(for: req)
                if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                    throw DBError.server("stream \(http.statusCode)")
                }
                backoff = 1
                var event = ""
                for try await line in bytes.lines {
                    if Task.isCancelled { return }
                    if line.hasPrefix("event:") {
                        event = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
                    } else if line.hasPrefix("data:") {
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if event == "auth_revoked" || event == "cancel" { break }
                        guard event == "put" || event == "patch",
                              let data = payload.data(using: .utf8),
                              let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? [String: Any],
                              let p = obj["path"] as? String else { continue }
                        apply(event: event, path: p, data: obj["data"])
                        let snapshot = tree
                        await MainActor.run { onChange(snapshot) }
                    }
                }
            } catch {
                if Task.isCancelled { return }
            }
            // Reconnect (also picks up a fresh login token).
            try? await Task.sleep(nanoseconds: backoff * 1_000_000_000)
            backoff = min(backoff * 2, 30)
        }
    }

    private func apply(event: String, path: String, data: Any?) {
        let parts = path.split(separator: "/").map(String.init)
        if event == "put" {
            tree = Self.set(tree, parts[...], data is NSNull ? nil : data)
        } else if let children = data as? [String: Any] {
            for (k, v) in children {
                tree = Self.set(tree, (parts + k.split(separator: "/").map(String.init))[...], v is NSNull ? nil : v)
            }
        }
    }

    private static func set(_ node: Any?, _ path: ArraySlice<String>, _ value: Any?) -> Any? {
        guard let key = path.first else { return value }
        var dict = node as? [String: Any] ?? [:]
        let child = set(dict[key], path.dropFirst(), value)
        if let child { dict[key] = child } else { dict.removeValue(forKey: key) }
        return dict.isEmpty ? nil : dict
    }
}
