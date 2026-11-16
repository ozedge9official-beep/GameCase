import Foundation

enum LCFileCopyError: Error { case cancelled }

struct LCProgressGate {
    private var lastReport: TimeInterval?
    mutating func shouldReport(now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
        if let lastReport, now - lastReport < 0.1 { return false }
        lastReport = now
        return true
    }
}

enum LCFileCopy {
    static let chunkSize = 4 * 1024 * 1024
    static func copy(from source: URL, to destination: URL, isCancelled: () -> Bool,
                     onProgress: (Int64) async -> Void) async throws -> Int64 {
        let fm = FileManager.default
        if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
        guard fm.createFile(atPath: destination.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
        let reader = try FileHandle(forReadingFrom: source)
        defer { try? reader.close() }
        let writer = try FileHandle(forWritingTo: destination)
        defer { try? writer.close() }
        var copied: Int64 = 0
        var gate = LCProgressGate()
        while true {
            if isCancelled() { throw LCFileCopyError.cancelled }
            let chunk = try reader.read(upToCount: chunkSize) ?? Data()
            if chunk.isEmpty { break }
            try writer.write(contentsOf: chunk)
            copied += Int64(chunk.count)
            if gate.shouldReport() { await onProgress(copied) }
        }
        try writer.synchronize()
        await onProgress(copied)
        return copied
    }
}
