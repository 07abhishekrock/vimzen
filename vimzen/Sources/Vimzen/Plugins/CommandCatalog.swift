import Foundation

/// Single source of truth for Ex-command documentation. Feeds the command-bar
/// hint list (CommandInputPlugin.queryItems) and the help page (HelpPageTemplate).
/// Execution stays in CommandInputPlugin.onSubmit — keep this catalog in sync
/// when adding commands there.
public struct CommandSpec: Sendable {
    public enum Section: String, Sendable, CaseIterable {
        case tabs = "Tabs"
        case profiles = "Profiles"
        case history = "History"
        case media = "Media"
        case privacy = "Privacy & Security"
        case general = "General"
    }

    public let name: String
    public let aliases: [String]
    public let argHint: String?
    public let blurb: String
    public let section: Section

    public init(_ name: String, aliases: [String] = [], argHint: String? = nil, blurb: String, section: Section) {
        self.name = name
        self.aliases = aliases
        self.argHint = argHint
        self.blurb = blurb
        self.section = section
    }
}

public enum CommandCatalog {
    public static let all: [CommandSpec] = [
        CommandSpec("q", blurb: "Close active tab (restore with u within 4s)", section: .tabs),
        CommandSpec("tabnew", aliases: ["t"], argHint: "[url]", blurb: "New scratchpad tab, or open URL in a new tab", section: .tabs),
        CommandSpec("b", aliases: ["tabs", "buffers"], blurb: "Fuzzy tab switcher", section: .tabs),
        CommandSpec("b#", blurb: "Switch to last active tab", section: .tabs),
        CommandSpec("alias", aliases: ["unalias"], argHint: "<name>", blurb: "Name this tab for the switcher (bare :alias or :unalias clears)", section: .tabs),

        CommandSpec("p", aliases: ["profile"], argHint: "[name | new <name>]", blurb: "Profile picker, or switch/create directly", section: .profiles),
        CommandSpec("p#", aliases: ["profile#"], blurb: "Switch to last active profile", section: .profiles),
        CommandSpec("send", aliases: ["transfer"], argHint: "<profile>", blurb: "Move active tab to another profile", section: .profiles),

        CommandSpec("history", blurb: "Fuzzy history picker", section: .history),
        CommandSpec("clearhistory", argHint: "[today | --domain <d> | all]", blurb: "Clear browsing history", section: .history),

        CommandSpec("mute", aliases: ["m"], blurb: "Mute/unmute active tab", section: .media),
        CommandSpec("unmute", blurb: "Unmute active tab", section: .media),
        CommandSpec("muteall", aliases: ["mute all"], blurb: "Mute/unmute all audible tabs", section: .media),
        CommandSpec("unmuteall", aliases: ["unmute all"], blurb: "Unmute every muted tab", section: .media),

        CommandSpec("clearcookies", argHint: "[all | --domain <d>]", blurb: "Clear cookies (active domain by default)", section: .privacy),
        CommandSpec("clearstorage", aliases: ["cleartokens"], argHint: "[--domain <d>]", blurb: "Clear localStorage/IndexedDB for a domain", section: .privacy),
        CommandSpec("forget", argHint: "[--domain <d>]", blurb: "Nuke a domain: cookies, storage, cache, history", section: .privacy),
        CommandSpec("js", aliases: ["toggle js"], argHint: "[on|off]", blurb: "Toggle JavaScript on this tab (session only)", section: .privacy),
        CommandSpec("cert", aliases: ["ssl"], blurb: "Inspect TLS certificate chain", section: .privacy),
        CommandSpec("domain", argHint: "[<key> on|off|reset]", blurb: "Per-domain settings, persisted across profiles", section: .privacy),

        CommandSpec("r", aliases: ["reload"], blurb: "Reload page", section: .general),
        CommandSpec("open", argHint: "<url>", blurb: "Open URL or search in current tab", section: .general),
        CommandSpec("qa", aliases: ["qall"], blurb: "Quit Vimzen", section: .general),
        CommandSpec("fullscreen", aliases: ["fs"], blurb: "Toggle native fullscreen", section: .general),
        CommandSpec("printpdf", aliases: ["pdf"], blurb: "Export page as PDF to ~/Downloads", section: .general),
        CommandSpec("scripts", blurb: "Open userscripts folder in Finder", section: .general),
        CommandSpec("reloadscripts", blurb: "Reload userscripts and the page", section: .general),
        CommandSpec("version", aliases: ["v"], blurb: "Show build info", section: .general),
        CommandSpec("help", aliases: ["h"], blurb: "Open the manual (vimzen://help)", section: .general),
    ]

    /// Resolves a typed command line (":send work", "mute all") to its canonical
    /// catalog name. Tries the first token, then the first two (multi-word aliases).
    public static func canonicalName(forCommandLine cmd: String) -> String? {
        let stripped = cmd.hasPrefix(":") ? String(cmd.dropFirst()) : cmd
        let tokens = stripped.split(separator: " ").map { $0.lowercased() }
        guard let first = tokens.first, !first.isEmpty else { return nil }
        if let hit = all.first(where: { $0.name == first || $0.aliases.contains(first) }) {
            return hit.name
        }
        if tokens.count >= 2 {
            let two = "\(tokens[0]) \(tokens[1])"
            if let hit = all.first(where: { $0.aliases.contains(two) }) {
                return hit.name
            }
        }
        return nil
    }

    public static func entry(named name: String) -> CommandSpec? {
        all.first { $0.name == name }
    }
}
