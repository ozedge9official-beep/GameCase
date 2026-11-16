import Foundation

/// Cost-limited values keyed by the current file version. File replacements,
/// edits and deletion cannot leave a persistent stale cache hit.
final class LCFileValueCache<Value: AnyObject> {
    private let cache = NSCache<NSString, Value>()
    init(costLimit: Int, countLimit: Int) {
        cache.totalCostLimit = costLimit
        cache.countLimit = countLimit
    }
    private func key(for url: URL) -> NSString? {
        guard let info = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modified = info[.modificationDate] as? Date,
              let size = info[.size] as? NSNumber else { return nil }
        return "\(url.standardizedFileURL.path)|\(modified.timeIntervalSince1970)|\(size)|\(info[.systemFileNumber] ?? "")" as NSString
    }
    func value(at url: URL, load: (URL) -> Value?, cost: (Value) -> Int) -> Value? {
        guard let version = key(for: url) else { return nil }
        if let hit = cache.object(forKey: version) { return hit }
        guard let value = load(url) else { return nil }
        if key(for: url) == version { cache.setObject(value, forKey: version, cost: cost(value)) }
        return value
    }
    func removeAll() { cache.removeAllObjects() }
}
