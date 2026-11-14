import Foundation

@MainActor
public enum NewTabTemplate {
    public static func html(userName: String = "Abhishek", initialNotes: String = "") -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        let dateStr = formatter.string(from: Date())

        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEEE"
        let dayName = dayFormatter.string(from: Date())

        let greeting = "Hi, \(userName). Today is \(dateStr) (\(dayName))"
        let escapedNotes = escapeHTML(initialNotes)

        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>
                * { box-sizing: border-box; margin: 0; padding: 0; }
                html, body {
                    background-color: #121214;
                    color: #ECECF1;
                    font-family: ui-monospace, 'SF Mono', 'JetBrains Mono', Menlo, Monaco, monospace;
                    height: 100vh;
                    display: flex;
                    flex-direction: column;
                    padding: 40px 56px;
                    overflow: hidden;
                    -webkit-font-smoothing: antialiased;
                }
                .header-container {
                    margin-bottom: 20px;
                    user-select: none;
                }
                .greeting {
                    font-size: 14px;
                    font-weight: 600;
                    color: #A1A1AA;
                    letter-spacing: -0.2px;
                    margin-bottom: 16px;
                }
                .divider {
                    height: 1px;
                    background: #27272A;
                    width: 100%;
                }
                .editor-container {
                    flex: 1;
                    display: flex;
                    flex-direction: column;
                }
                textarea {
                    flex: 1;
                    width: 100%;
                    background: transparent;
                    border: none;
                    outline: none;
                    resize: none;
                    color: #F4F4F5;
                    font-family: ui-monospace, 'SF Mono', 'JetBrains Mono', Menlo, Monaco, monospace;
                    font-size: 13px;
                    line-height: 1.68;
                    tab-size: 2;
                    caret-color: #5AC8FA;
                }
                textarea::placeholder {
                    color: #52525B;
                }
            </style>
        </head>
        <body>
            <div class="header-container">
                <div class="greeting">\(greeting)</div>
                <div class="divider"></div>
            </div>
            <div class="editor-container">
                <textarea id="pad" placeholder="Type markdown notes here... ('i' to edit, 'esc' for normal mode, 'o' to open url)" spellcheck="false" autofocus>\(escapedNotes)</textarea>
            </div>
            <script>
                const pad = document.getElementById('pad');

                // Caret starts after any restored notes, not at position 0
                pad.focus();
                pad.setSelectionRange(pad.value.length, pad.value.length);

                // Save notes to native Swift on input (which writes to ~/.config or AppSupport .md)
                pad.addEventListener('input', () => {
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.vimzen) {
                        window.webkit.messageHandlers.vimzen.postMessage({
                            action: 'saveScratchpad',
                            text: pad.value
                        });
                    }
                });

                // Tab key indents with 2 spaces
                pad.addEventListener('keydown', (e) => {
                    if (e.key === 'Tab') {
                        e.preventDefault();
                        const start = pad.selectionStart;
                        const end = pad.selectionEnd;
                        pad.value = pad.value.substring(0, start) + '  ' + pad.value.substring(end);
                        pad.selectionStart = pad.selectionEnd = start + 2;
                        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.vimzen) {
                            window.webkit.messageHandlers.vimzen.postMessage({
                                action: 'saveScratchpad',
                                text: pad.value
                            });
                        }
                    }
                });
            </script>
        </body>
        </html>
        """
    }

    private static func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
