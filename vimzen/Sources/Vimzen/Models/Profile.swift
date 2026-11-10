import AppKit

public struct Profile: Identifiable, Sendable, Hashable {
    public let id: UUID
    public var name: String
    public var badge: String
    public var iconName: String
    public var isEphemeral: Bool
    public var colorHex: String

    public init(
        id: UUID = UUID(),
        name: String,
        badge: String,
        iconName: String = "person.fill",
        isEphemeral: Bool = false,
        colorHex: String = "#5AC8FA"
    ) {
        self.id = id
        self.name = name
        self.badge = badge
        self.iconName = iconName
        self.isEphemeral = isEphemeral
        self.colorHex = colorHex
    }

    public static let personal = Profile(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        name: "Personal",
        badge: "pers",
        iconName: "person.fill",
        isEphemeral: false,
        colorHex: "#5AC8FA"
    )

    public static let work = Profile(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        name: "Work",
        badge: "work",
        iconName: "briefcase.fill",
        isEphemeral: false,
        colorHex: "#FF9500"
    )

    public static let incognito = Profile(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
        name: "Incognito",
        badge: "anon",
        iconName: "eyeglasses",
        isEphemeral: true,
        colorHex: "#AF52DE"
    )
}
