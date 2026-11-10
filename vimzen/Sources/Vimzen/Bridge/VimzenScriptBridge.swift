import AppKit
import WebKit

@MainActor
public final class VimzenScriptBridge: NSObject, WKScriptMessageHandler {
    public weak var tab: Tab?

    public static let injectedScriptSource: String = """
    (function() {
        if (!window.vimzen) {
            window.vimzen = {
                setTopColor: function(color) {
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.vimzen) {
                        window.webkit.messageHandlers.vimzen.postMessage({
                            action: 'setTopColor',
                            color: String(color)
                        });
                    }
                },
                resetTopColor: function() {
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.vimzen) {
                        window.webkit.messageHandlers.vimzen.postMessage({
                            action: 'resetTopColor'
                        });
                    }
                },
                showToast: function(message, duration) {
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.vimzen) {
                        window.webkit.messageHandlers.vimzen.postMessage({
                            action: 'showToast',
                            message: String(message),
                            duration: Number(duration) || 3.0
                        });
                    }
                },
                exec: function(command) {
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.vimzen) {
                        window.webkit.messageHandlers.vimzen.postMessage({
                            action: 'exec',
                            command: String(command)
                        });
                    }
                }
            };
        }

        // Media & Audio Monitor
        if (!window._vimzenMediaMonitored) {
            window._vimzenMediaMonitored = true;
            const audioContexts = [];
            const OrigCtx = window.AudioContext || window.webkitAudioContext;
            if (OrigCtx) {
                try {
                    window.AudioContext = function() {
                        const ctx = new OrigCtx(...arguments);
                        audioContexts.push(ctx);
                        return ctx;
                    };
                    window.AudioContext.prototype = OrigCtx.prototype;
                } catch (e) {}
            }

            function checkMedia() {
                const elements = Array.from(document.querySelectorAll('video, audio'));
                let isAudible = false;
                let isPlaying = false;
                let anyMuted = false;
                let kind = 'none';

                for (const el of elements) {
                    if (!el.paused && !el.ended) {
                        isPlaying = true;
                        if (el.tagName.toLowerCase() === 'video') {
                            kind = 'video';
                        } else if (kind === 'none') {
                            kind = 'audio';
                        }
                        if (!el.muted && el.volume > 0) {
                            isAudible = true;
                        }
                        if (el.muted || el.volume === 0) {
                            anyMuted = true;
                        }
                    }
                }

                // Only report state if active media was found or if this is the top frame
                if (isPlaying || isAudible || window === window.top) {
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.vimzen) {
                        window.webkit.messageHandlers.vimzen.postMessage({
                            action: 'mediaStateChanged',
                            isAudible: isAudible,
                            isPlaying: isPlaying,
                            isMuted: anyMuted,
                            mediaKind: kind
                        });
                    }
                }
            }

            document.addEventListener('play', checkMedia, true);
            document.addEventListener('playing', checkMedia, true);
            document.addEventListener('pause', checkMedia, true);
            document.addEventListener('ended', checkMedia, true);
            document.addEventListener('volumechange', checkMedia, true);

            window.vimzenMuteMedia = function(mute) {
                document.querySelectorAll('video, audio').forEach(el => {
                    el.muted = mute;
                });
                audioContexts.forEach(ctx => {
                    try {
                        if (mute && ctx.state === 'running') ctx.suspend();
                        else if (!mute && ctx.state === 'suspended') ctx.resume();
                    } catch (e) {}
                });
                checkMedia();
            };

            setInterval(checkMedia, 2000);
            setTimeout(checkMedia, 1000);
        }
    })();
    """

    public func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == "vimzen",
              let body = message.body as? [String: Any],
              let action = body["action"] as? String else {
            return
        }

        switch action {
        case "setTopColor":
            if let colorStr = body["color"] as? String,
               let parsed = ColorParser.parse(colorStr) {
                tab?.setCustomTopColor(parsed)
            }

        case "resetTopColor":
            tab?.setCustomTopColor(nil)

        case "showToast":
            let msg = body["message"] as? String ?? ""
            let dur = body["duration"] as? Double ?? 3.0
            PluginRegistry.shared.showToast(NotificationToast(message: msg, duration: dur))

        case "exec":
            if let cmd = body["command"] as? String,
               let mainVC = NSApp.keyWindow?.contentViewController as? MainViewController {
                CommandInputPlugin().onSubmit(input: cmd, controller: mainVC)
            }

        case "saveScratchpad":
            if let text = body["text"] as? String, let profileId = tab?.profileId {
                ScratchpadStore.saveNotes(text, for: profileId)
            }

        case "mediaStateChanged":
            let isAudible = body["isAudible"] as? Bool ?? false
            let isPlaying = body["isPlaying"] as? Bool ?? false
            let isMuted = body["isMuted"] as? Bool ?? false
            let mediaKind = body["mediaKind"] as? String ?? "none"
            tab?.updateMediaState(isAudible: isAudible, isPlaying: isPlaying, isMuted: isMuted, mediaKind: mediaKind)

        default:
            break
        }
    }
}
