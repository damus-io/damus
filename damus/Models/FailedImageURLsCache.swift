
import Foundation

final class FailedImageURLsCache {
    static let notification = Notification.Name("FailedImageURLsDidChange")
    
    private(set) var urls = Set<URL>()
    
    func add(_ url: URL) {
        let shouldNotify = !urls.contains(url)
        urls.insert(url)
        if shouldNotify {
            NotificationCenter.default.post(name: FailedImageURLsCache.notification, object: nil)
        }
    }
}
