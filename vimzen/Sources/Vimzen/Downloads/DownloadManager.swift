import AppKit
import WebKit

@MainActor
public final class DownloadManager: NSObject, WKDownloadDelegate {
    public static let shared = DownloadManager()

    public private(set) var activeDownloads: [WKDownload: String] = [:]

    public func track(_ download: WKDownload, suggestedFilename: String = "download") {
        download.delegate = self
        activeDownloads[download] = suggestedFilename
    }

    // MARK: - WKDownloadDelegate

    public func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String,
        completionHandler: @escaping @MainActor @Sendable (URL?) -> Void
    ) {
        let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads", isDirectory: true)

        let safeName = suggestedFilename.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "download"
            : suggestedFilename

        let destURL = resolveUniqueURL(in: downloadsDir, filename: safeName)
        activeDownloads[download] = destURL.lastPathComponent

        completionHandler(destURL)
    }

    public func downloadDidFinish(_ download: WKDownload) {
        let filename = activeDownloads.removeValue(forKey: download) ?? "file"
        PluginRegistry.shared.showToast(
            NotificationToast(
                message: "Downloaded: \(filename)",
                duration: 2.5
            )
        )
    }

    public func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        let filename = activeDownloads.removeValue(forKey: download) ?? "file"
        PluginRegistry.shared.showToast(
            NotificationToast(
                message: "Download failed: \(filename)",
                duration: 2.5
            )
        )
    }

    private func resolveUniqueURL(in directory: URL, filename: String) -> URL {
        let fm = FileManager.default
        var targetURL = directory.appendingPathComponent(filename)
        if !fm.fileExists(atPath: targetURL.path) {
            return targetURL
        }

        let baseName = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        var index = 1

        while true {
            let candidateName = ext.isEmpty ? "\(baseName) (\(index))" : "\(baseName) (\(index)).\(ext)"
            targetURL = directory.appendingPathComponent(candidateName)
            if !fm.fileExists(atPath: targetURL.path) {
                return targetURL
            }
            index += 1
        }
    }
}
