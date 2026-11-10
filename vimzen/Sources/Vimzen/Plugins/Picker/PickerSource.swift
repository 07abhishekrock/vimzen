import Foundation

public enum PickerSourceKind: String, Sendable {
    case openTab
    case googleSuggest
    // Forward-compatible extensions for future milestones:
    case typedHistory
    case linkHistory
    case command
}

public struct PickerItem: Sendable {
    public let id: String
    public let display: String
    public let detail: String?
    public let badge: String
    public let url: URL?
    public let title: String?
    public let source: PickerSourceKind
    public let visitCount: Int
    public let lastVisitAt: Date?
    public let typedCount: Int

    public init(
        id: String,
        display: String,
        detail: String? = nil,
        badge: String,
        url: URL? = nil,
        title: String? = nil,
        source: PickerSourceKind,
        visitCount: Int = 0,
        lastVisitAt: Date? = nil,
        typedCount: Int = 0
    ) {
        self.id = id
        self.display = display
        self.detail = detail
        self.badge = badge
        self.url = url
        self.title = title
        self.source = source
        self.visitCount = visitCount
        self.lastVisitAt = lastVisitAt
        self.typedCount = typedCount
    }
}

@MainActor
public protocol PickerSource: AnyObject {
    var sourceKind: PickerSourceKind { get }
    var badge: String { get }
    func items(matching query: String) async throws -> [PickerItem]
}
