import Foundation

/// E2E test support. When the app is launched with `--vimzen-test-dir <path>`,
/// all mutable state (history DB, scratchpads, website data stores) is redirected
/// into that directory and the window frame is made deterministic.
/// Without the flag the app behaves exactly as before.
public enum TestEnvironment {
    public static let dataDirectory: URL? = {
        let args = ProcessInfo.processInfo.arguments
        guard let flagIndex = args.firstIndex(of: "--vimzen-test-dir"),
              args.count > flagIndex + 1 else {
            return nil
        }
        return URL(fileURLWithPath: args[flagIndex + 1], isDirectory: true)
    }()

    public static var isEnabled: Bool { dataDirectory != nil }
}
