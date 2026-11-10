import AppKit
import WebKit

@MainActor
public final class UserScriptManager {
    public static let shared = UserScriptManager()

    public let scriptsDirectory: URL

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".config/vimzen/scripts", isDirectory: true)
        self.scriptsDirectory = dir

        ensureDirectoryAndSampleScript()
    }

    private func ensureDirectoryAndSampleScript() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: scriptsDirectory.path) {
            try? fm.createDirectory(at: scriptsDirectory, withIntermediateDirectories: true)

            // Create a helpful sample userscript
            let sampleFile = scriptsDirectory.appendingPathComponent("example_theme.js")
            let sampleContent = """
            // Vimzen Userscript Example
            // You can use window.vimzen here to customize UI colors, show toasts, or run commands.

            (function() {
                if (!window.vimzen) return;

                // Example: set dark charcoal top bar for GitHub
                if (location.hostname.includes('github.com')) {
                    window.vimzen.setTopColor('#161b22');
                }
            })();
            """
            try? sampleContent.write(to: sampleFile, atomically: true, encoding: .utf8)
        }
    }

    public func loadScripts() -> [String] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: scriptsDirectory, includingPropertiesForKeys: nil) else {
            return []
        }

        var scripts: [String] = []
        for file in files where file.pathExtension == "js" {
            if let content = try? String(contentsOf: file, encoding: .utf8), !content.isEmpty {
                scripts.append(content)
            }
        }
        return scripts
    }

    public func attachUserScripts(to userContentController: WKUserContentController) {
        let scripts = loadScripts()
        for source in scripts {
            let userScript = WKUserScript(
                source: source,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
            userContentController.addUserScript(userScript)
        }
    }
}
