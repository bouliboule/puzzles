import Foundation

/// Key/value persistence; same keys as the web app's localStorage and
/// the Android app's SharedPreferences. Thread-safe (UserDefaults).
final class Store: @unchecked Sendable {
    private let d = UserDefaults.standard
    private func k(_ key: String) -> String { "pz:" + key }

    func str(_ key: String) -> String? { d.string(forKey: k(key)) }

    func json(_ key: String) -> [String: Any]? {
        guard let s = str(key), let data = s.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    func set(_ key: String, _ v: String) { d.set(v, forKey: k(key)) }

    func set(_ key: String, json v: [String: Any]) {
        if let data = try? JSONSerialization.data(withJSONObject: v), let s = String(data: data, encoding: .utf8) {
            set(key, s)
        }
    }

    func del(_ key: String) { d.removeObject(forKey: k(key)) }
}

/// Per-puzzle progress for the current game.
struct Meta {
    var params: String
    var label = ""
    var elapsed: Double = 0
    var solved = false
    var helped = false

    var json: [String: Any] {
        ["params": params, "label": label, "elapsed": elapsed, "solved": solved, "helped": helped]
    }

    init(params: String, label: String = "") {
        self.params = params
        self.label = label
    }

    init(json o: [String: Any]?, defaultParams: String) {
        let p = o?["params"] as? String ?? ""
        params = p.isEmpty ? defaultParams : p
        label = o?["label"] as? String ?? ""
        elapsed = (o?["elapsed"] as? NSNumber)?.doubleValue ?? 0
        solved = o?["solved"] as? Bool ?? false
        helped = o?["helped"] as? Bool ?? false
    }
}

/// Generates puzzles off the main thread with drawing-less midends, and
/// keeps one ready-made puzzle per type ("<name>:next") so New game is
/// instant. Plays the role of web/js/gen-worker.js.
final class Generator: @unchecked Sendable {
    private let store: Store
    private let lock = NSLock()
    private var handles: [String: PZ] = [:]   // only touched while holding `lock`

    init(store: Store) { self.store = store }

    /// Runs work on a thread with a large stack (some generators recurse deeply), one job at a time.
    private func run(_ work: @escaping @Sendable () -> Void) {
        let t = Thread { [lock] in
            lock.lock(); defer { lock.unlock() }
            work()
        }
        t.stackSize = 16 << 20
        t.qualityOfService = .userInitiated
        t.start()
    }

    private func generate(_ name: String, _ params: String) throws -> String {
        let h: PZ
        if let existing = handles[name] { h = existing }
        else {
            guard let n = PZ(name: name, renderer: nil) else { throw Message("Unknown puzzle \(name)") }
            handles[name] = n
            h = n
        }
        let id = h.generate(params)
        if id.isEmpty { throw Message("Invalid parameters: \(params)") }
        return id
    }

    /// A game ID for name/params, using the prefetched one if it matches.
    func take(_ name: String, _ params: String) async throws -> String {
        if let next = store.json("\(name):next"), next["params"] as? String == params,
           let id = next["gameId"] as? String, !id.isEmpty {
            store.del("\(name):next")
            return id
        }
        return try await withCheckedThrowingContinuation { cont in
            run { [self] in cont.resume(with: Result { try generate(name, params) }) }
        }
    }

    func prefetch(_ name: String, _ params: String) {
        if store.json("\(name):next")?["params"] as? String == params { return }
        run { [self] in
            if let id = try? generate(name, params) {
                store.set("\(name):next", json: ["params": params, "gameId": id])
            }
        }
    }
}
