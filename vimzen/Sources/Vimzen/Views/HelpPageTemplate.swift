import Foundation

@MainActor
public enum HelpPageTemplate {
    public static func html() -> String {
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Vimzen Help</title>
            <style>
                * { box-sizing: border-box; margin: 0; padding: 0; }
                html, body {
                    background-color: #121214;
                    color: #ECECF1;
                    font-family: ui-monospace, 'SF Mono', 'JetBrains Mono', Menlo, Monaco, monospace;
                    padding: 48px 64px;
                    line-height: 1.6;
                    -webkit-font-smoothing: antialiased;
                }
                .container {
                    max-width: 900px;
                    margin: 0 auto;
                }
                header {
                    margin-bottom: 40px;
                    border-bottom: 1px solid #27272A;
                    padding-bottom: 24px;
                }
                h1 {
                    font-size: 22px;
                    font-weight: 700;
                    color: #FFFFFF;
                    letter-spacing: -0.5px;
                    margin-bottom: 8px;
                }
                .subtitle {
                    font-size: 13px;
                    color: #A1A1AA;
                    margin-bottom: 16px;
                }
                .search-tip {
                    display: inline-block;
                    font-size: 12px;
                    color: #5AC8FA;
                    background: rgba(90, 200, 250, 0.10);
                    border: 1px solid rgba(90, 200, 250, 0.25);
                    padding: 6px 12px;
                    border-radius: 4px;
                }
                .section {
                    margin-bottom: 36px;
                }
                h2 {
                    font-size: 14px;
                    text-transform: uppercase;
                    letter-spacing: 0.5px;
                    color: #71717A;
                    margin-bottom: 16px;
                    padding-bottom: 6px;
                    border-bottom: 1px solid #1E1E22;
                }
                table {
                    width: 100%;
                    border-collapse: collapse;
                    font-size: 13px;
                }
                tr {
                    border-bottom: 1px solid #18181B;
                }
                tr:last-child {
                    border-bottom: none;
                }
                td {
                    padding: 10px 12px;
                    vertical-align: top;
                }
                td.keys {
                    width: 220px;
                    white-space: nowrap;
                }
                kbd {
                    display: inline-block;
                    background: #27272A;
                    color: #F4F4F5;
                    padding: 2px 6px;
                    border-radius: 3px;
                    font-size: 11px;
                    font-family: inherit;
                    border: 1px solid #3F3F46;
                    box-shadow: 0 1px 0 rgba(0,0,0,0.2);
                }
                kbd + kbd {
                    margin-left: 4px;
                }
                .sep {
                    color: #52525B;
                    margin: 0 4px;
                }
                .desc {
                    color: #D4D4D8;
                }
                .note {
                    color: #71717A;
                    font-size: 11px;
                    margin-left: 6px;
                }
                footer {
                    margin-top: 60px;
                    padding-top: 20px;
                    border-top: 1px solid #27272A;
                    text-align: center;
                    color: #52525B;
                    font-size: 11px;
                }
            </style>
        </head>
        <body>
            <div class="container">
                <header>
                    <h1>Vimzen Manual & Keymap</h1>
                    <div class="subtitle">A keyboard-first browser with Vim modal keybindings, zen-minimal UI, and profiles.</div>
                    <div class="search-tip">💡 Tip: Press <kbd>/</kbd> anywhere on this page to live-search any shortcut or command.</div>
                </header>

                <div class="section">
                    <h2>Navigation & Scrolling</h2>
                    <table>
                        <tr>
                            <td class="keys"><kbd>j</kbd><span class="sep">/</span><kbd>k</kbd></td>
                            <td class="desc">Scroll down / up by line <span class="note">(supports count, e.g. 10j)</span></td>
                        </tr>
                        <tr>
                            <td class="keys"><kbd>h</kbd><span class="sep">/</span><kbd>l</kbd></td>
                            <td class="desc">Scroll left / right</td>
                        </tr>
                        <tr>
                            <td class="keys"><kbd>gg</kbd><span class="sep">/</span><kbd>G</kbd></td>
                            <td class="desc">Jump to top / bottom of document</td>
                        </tr>
                        <tr>
                            <td class="keys"><kbd>Ctrl</kbd>+<kbd>d</kbd><span class="sep">/</span><kbd>Ctrl</kbd>+<kbd>u</kbd></td>
                            <td class="desc">Scroll half-page down / up</td>
                        </tr>
                        <tr>
                            <td class="keys"><kbd>Ctrl</kbd>+<kbd>f</kbd><span class="sep">/</span><kbd>Ctrl</kbd>+<kbd>b</kbd></td>
                            <td class="desc">Scroll full-page down / up</td>
                        </tr>
                        <tr>
                            <td class="keys"><kbd>H</kbd><span class="sep">/</span><kbd>L</kbd></td>
                            <td class="desc">Navigate history back / forward <span class="note">(or ⌘[ / ⌘])</span></td>
                        </tr>
                        <tr>
                            <td class="keys"><kbd>r</kbd><span class="sep">/</span><kbd>R</kbd></td>
                            <td class="desc">Reload page / Hard reload <span class="note">(bypass cache)</span></td>
                        </tr>
                    </table>
                </div>

                <div class="section">
                    <h2>Address Bar & Modes</h2>
                    <table>
                        <tr>
                            <td class="keys"><kbd>o</kbd></td>
                            <td class="desc">Open address bar / search in current tab</td>
                        </tr>
                        <tr>
                            <td class="keys"><kbd>O</kbd></td>
                            <td class="desc">Open address bar / search in new tab</td>
                        </tr>
                        <tr>
                            <td class="keys"><kbd>:</kbd></td>
                            <td class="desc">Enter Ex-command line mode <span class="note">(hint list filters as you type; commands run only when entered in full)</span></td>
                        </tr>
                        <tr>
                            <td class="keys"><kbd>?</kbd></td>
                            <td class="desc">Open this manual (<code>vimzen://help</code>)</td>
                        </tr>
                        <tr>
                            <td class="keys"><kbd>i</kbd></td>
                            <td class="desc">Enter INSERT mode <span class="note">(keys pass directly to webpage or scratchpad)</span></td>
                        </tr>
                        <tr>
                            <td class="keys"><kbd>Esc</kbd><span class="sep">/</span><kbd>Ctrl</kbd>+<kbd>[</kbd></td>
                            <td class="desc">Return to NORMAL mode <span class="note">(dismisses prompts & clears search)</span></td>
                        </tr>
                        <tr>
                            <td class="keys"><kbd>Ctrl</kbd>+<kbd>Enter</kbd></td>
                            <td class="desc">In address bar: force open custom query in a <strong>new tab</strong></td>
                        </tr>
                    </table>
                </div>

                <div class="section">
                    <h2>Tabs & Switching</h2>
                    <table>
                        <tr>
                            <td class="keys"><kbd>gt</kbd><span class="sep">/</span><kbd>gT</kbd></td>
                            <td class="desc">Switch to next / previous tab in active profile</td>
                        </tr>
                        <tr>
                            <td class="keys"><kbd>gd</kbd><span class="sep">/</span><kbd>gD</kbd></td>
                            <td class="desc">Cycle between tabs sharing the active tab's domain</td>
                        </tr>
                        <tr>
                            <td class="keys"><kbd>Ctrl</kbd>+<kbd>6</kbd><span class="sep">/</span><kbd>g</kbd> <kbd>Tab</kbd></td>
                            <td class="desc">Toggle back and forth to last active tab <span class="note">(:b#)</span></td>
                        </tr>
                        <tr>
                            <td class="keys"><kbd>b</kbd><span class="sep">/</span><kbd>T</kbd></td>
                            <td class="desc">Fuzzy tab switcher <span class="note">(filter open tabs with &lt;C-j&gt;/&lt;C-k&gt;)</span></td>
                        </tr>
                        <tr>
                            <td class="keys"><kbd>x</kbd><span class="sep">/</span><kbd>⌘W</kbd></td>
                            <td class="desc">Close active tab <span class="note">(triggers 4s undo toast)</span></td>
                        </tr>
                        <tr>
                            <td class="keys"><kbd>u</kbd></td>
                            <td class="desc">Undo closed tab <span class="note">(press within 4 seconds of closing)</span></td>
                        </tr>
                        <tr>
                            <td class="keys"><kbd>⌘T</kbd></td>
                            <td class="desc">Open a new tab with the markdown scratchpad</td>
                        </tr>
                    </table>
                </div>

                <div class="section">
                    <h2>Profiles & Workspaces (Model B)</h2>
                    <table>
                        <tr>
                            <td class="keys"><kbd>gp</kbd></td>
                            <td class="desc">Open Profile Switcher <span class="note">(switch between Personal, Work, Incognito)</span></td>
                        </tr>
                        <tr>
                            <td class="keys"><kbd>gP</kbd></td>
                            <td class="desc">Move active tab to another profile workspace and switch to follow</td>
                        </tr>
                        <tr>
                            <td class="keys"><kbd>Ctrl</kbd>+<kbd>p</kbd></td>
                            <td class="desc">Alternate between two most recent profiles</td>
                        </tr>
                    </table>
                </div>

                <div class="section">
                    <h2>In-Page Find / Search</h2>
                    <table>
                        <tr>
                            <td class="keys"><kbd>/</kbd></td>
                            <td class="desc">Start in-page search <span class="note">(live [idx/total] count as you type)</span></td>
                        </tr>
                        <tr>
                            <td class="keys"><kbd>n</kbd></td>
                            <td class="desc">Jump to next match forward <span class="note">(supports count: 3n)</span></td>
                        </tr>
                        <tr>
                            <td class="keys"><kbd>N</kbd></td>
                            <td class="desc">Jump to previous match backward <span class="note">(supports count: 2N)</span></td>
                        </tr>
                        <tr>
                            <td class="keys"><kbd>Esc</kbd></td>
                            <td class="desc">In NORMAL mode: clear all search highlights</td>
                        </tr>
                    </table>
                </div>

                <div class="section">
                    <h2>Media & Sound Controls</h2>
                    <table>
                        <tr>
                            <td class="keys"><kbd>Ctrl</kbd>+<kbd>m</kbd></td>
                            <td class="desc">Mute / unmute active tab <span class="note">(:mute / :unmute)</span></td>
                        </tr>
                        <tr>
                            <td class="keys"><kbd>Ctrl</kbd>+<kbd>Shift</kbd>+<kbd>m</kbd></td>
                            <td class="desc">Mute / unmute all audible tabs <span class="note">(:muteall / :unmuteall)</span></td>
                        </tr>
                        <tr>
                            <td class="keys"><kbd>M</kbd><span class="sep">/</span><kbd>gm</kbd></td>
                            <td class="desc">Cycle forward through playing media tabs in ring order</td>
                        </tr>
                        <tr>
                            <td class="keys"><kbd>gM</kbd></td>
                            <td class="desc">Cycle backward through playing media tabs</td>
                        </tr>
                    </table>
                </div>

                <div class="section">
                    <h2>History & SQLite</h2>
                    <table>
                        <tr>
                            <td class="keys"><kbd>gh</kbd><span class="sep">/</span><kbd>,h</kbd></td>
                            <td class="desc">Open fuzzy history picker <span class="note">(localized to active profile)</span></td>
                        </tr>
                    </table>
                </div>

                \(commandSectionsHTML)

                <footer>
                    Vimzen Browser &middot; Engineered with Swift, AppKit &amp; WebKit &middot; Local-First &amp; Distraction-Free
                </footer>
            </div>
        </body>
        </html>
        """
    }

    /// Command tables generated from CommandCatalog — the same source the
    /// command-bar hint list uses, so the two can never drift apart.
    private static var commandSectionsHTML: String {
        CommandSpec.Section.allCases.map { section in
            let rows = CommandCatalog.all
                .filter { $0.section == section }
                .map { spec -> String in
                    var keys = "<kbd>:\(spec.name)</kbd>"
                    if let hint = spec.argHint {
                        keys += " <span class=\"note\">\(escapeHTML(hint))</span>"
                    }
                    let aliasNote = spec.aliases.isEmpty
                        ? ""
                        : " <span class=\"note\">(:\(spec.aliases.joined(separator: ", :")))</span>"
                    return "<tr><td class=\"keys\">\(keys)</td><td class=\"desc\">\(escapeHTML(spec.blurb))\(aliasNote)</td></tr>"
                }
                .joined()
            return """
            <div class="section">
                <h2>Commands · \(section.rawValue)</h2>
                <table>\(rows)</table>
            </div>
            """
        }
        .joined(separator: "\n")
    }

    private static func escapeHTML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
