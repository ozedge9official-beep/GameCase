import Foundation

enum LCStorageError: Error {
    case insufficientSpace(required: Int64, available: Int64)
    case archiveSpace
    case invalidSize
}

enum LCStorageCapacity {
    static func available(at url: URL) -> Int64? {
        var existing = url
        while !FileManager.default.fileExists(atPath: existing.path), existing.path != "/" {
            existing.deleteLastPathComponent()
        }
        if let values = try? existing.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let bytes = values.volumeAvailableCapacityForImportantUsage { return max(0, bytes) }
        let values = try? FileManager.default.attributesOfFileSystem(forPath: existing.path)
        return (values?[.systemFreeSize] as? NSNumber)?.int64Value
    }

    static func required(for sizes: [Int64]) throws -> Int64 {
        var total: Int64 = 0
        for size in sizes {
            guard size >= 0, size <= Int64.max - total else { throw LCStorageError.invalidSize }
            total += size
        }
        let reserve = max(4 * 1024 * 1024, total / 100)
        guard reserve <= Int64.max - total else { throw LCStorageError.invalidSize }
        return total + reserve
    }

    static func check(sizes: [Int64], at url: URL, capacity: (URL) -> Int64? = available) throws {
        let required = try required(for: sizes)
        // Some Files providers do not report capacity. Actual I/O errors and
        // transaction rollback still apply when a preflight is unavailable.
        if let bytes = capacity(url), bytes < required {
            throw LCStorageError.insufficientSpace(required: required, available: bytes)
        }
    }
}
