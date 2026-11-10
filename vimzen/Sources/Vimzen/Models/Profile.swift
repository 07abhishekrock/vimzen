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
        id: UUID(uuidString: "A1B2C3D4-E5F6-4A7B-8C9D-0E1F2A3B4C5D")!,
        name: "Personal",
        badge: "pers",
        iconName: "person.fill",
        isEphemeral: false,
        colorHex: "#5AC8FA"
    )

    public static let work = Profile(
        id: UUID(uuidString: "B2C3D4E5-F6A7-4B8C-9D0E-1F2A3B4C5D6E")!,
        name: "Work",
        badge: "work",
        iconName: "briefcase.fill",
        isEphemeral: false,
        colorHex: "#FF9500"
    )

    public static let incognito = Profile(
        id: UUID(uuidString: "C3D4E5F6-A7B8-4C9D-0E1F-2A3B4C5D6E7F")!,
        name: "Incognito",
        badge: "anon",
        iconName: "eyeglasses",
        isEphemeral: true,
        colorHex: "#AF52DE"
    )
}
