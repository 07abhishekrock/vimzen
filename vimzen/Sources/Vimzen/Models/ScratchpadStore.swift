import Foundation

@MainActor
public enum ScratchpadStore {
    private static var scratchpadsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Vimzen/scratchpads", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func fileURL(for profileId: UUID) -> URL {
        scratchpadsDirectory.appendingPathComponent("\(profileId.uuidString).md")
    }

    public static func loadNotes(for profileId: UUID) -> String {
        let url = fileURL(for: profileId)
        if let text = try? String(contentsOf: url, encoding: .utf8) {
            return text
        }
        return ""
    }

    public static func saveNotes(_ notes: String, for profileId: UUID) {
        let url = fileURL(for: profileId)
        try? notes.write(to: url, atomically: true, encoding: .utf8)
    }
}
