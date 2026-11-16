import UIKit

enum LCCoverImageCache {
    private static let images = LCFileValueCache<UIImage>(costLimit: 48 * 1024 * 1024, countLimit: 32)
    private static let memoryWarning = NotificationCenter.default.addObserver(
        forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: nil
    ) { _ in images.removeAll() }

    static func image(at url: URL) -> UIImage? {
        _ = memoryWarning
        return images.value(at: url, load: { UIImage(contentsOfFile: $0.path) }, cost: { image in
            if let cg = image.cgImage { return cg.bytesPerRow * cg.height }
            return Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        })
    }
    static func removeAll() { images.removeAll() }
}
