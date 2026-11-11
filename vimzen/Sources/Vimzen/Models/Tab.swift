import AppKit
import WebKit
import Combine
import Security

@MainActor
public final class Tab: NSObject, Identifiable, ObservableObject, WKNavigationDelegate {
    public let id: UUID
    public let profileId: UUID
    public let webView: WKWebView

    /// Back-reference for WKUIDelegate flows (popups, window.close) that must
    /// create or close tabs. Set by TabManager immediately after init.
    public weak var tabManager: TabManager?

    @Published public var title: String = ""
    @Published public var url: URL?
    @Published public var faviconURL: URL?
    @Published public var isLoading: Bool = false
    @Published public var estimatedProgress: Double = 0.0
    @Published public var canGoBack: Bool = false
    @Published public var canGoForward: Bool = false
    @Published public var isJavaScriptEnabled: Bool = true
    @Published public private(set) var topColor: NSColor? = nil
    @Published public var isAudible: Bool = false
    @Published public var isPlayingMedia: Bool = false
    @Published public var isMuted: Bool = false
    @Published public var mediaKind: String = "none"
    @Published public var alias: String? = nil
    public var lastSearchQuery: String = ""
    public var currentSearchIndex: Int = 0
    public var totalSearchMatches: Int = 0
    public private(set) var lastAudibleAt: Date? = nil
    public private(set) var currentServerTrust: SecTrust?
    public private(set) var isNewTabScratchpad: Bool = false
    public private(set) var lastActiveAt: Date = Date()
    public private(set) var failedURL: URL? = nil
    private var provisionalTargetURL: URL? = nil
    /// Set only by load(url:) — never touched by delegate callbacks, so provisional
    /// failures can always be attributed even if webView.url still shows the old page.
    private var lastRequestedURL: URL? = nil

    private var customTopColor: NSColor? = nil
    private var detectedTopColor: NSColor? = nil
    private var silenceDebounceTask: Task<Void, Never>?
    private var bypassInsecureWarningURLs = Set<URL>()
    private var popupConfirmPending = false
    private let scriptBridge = VimzenScriptBridge()

    public func markActive() {
        lastActiveAt = Date()
    }

    public func setAlias(_ newAlias: String?) {
        let trimmed = newAlias?.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "^@", with: "", options: .regularExpression)
        if let t = trimmed, !t.isEmpty {
            alias = t
        } else {
            alias = nil
        }
    }

    private var cancellables = Set<AnyCancellable>()

    public init(
        id: UUID = UUID(),
        profileId: UUID = ProfileManager.shared.activeProfileId,
        webViewConfiguration: WKWebViewConfiguration = WKWebViewConfiguration()
    ) {
        self.id = id
        self.profileId = profileId

        // Configure modern WKWebView settings
        webViewConfiguration.allowsAirPlayForMediaPlayback = true
        webViewConfiguration.mediaTypesRequiringUserActionForPlayback = .all
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        webViewConfiguration.defaultWebpagePreferences = preferences

        // Inject window.vimzen bridge script
        let userScript = WKUserScript(
            source: VimzenScriptBridge.injectedScriptSource,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        webViewConfiguration.userContentController.addUserScript(userScript)
        webViewConfiguration.userContentController.add(scriptBridge, name: "vimzen")

        // Attach custom userscripts from ~/.config/vimzen/scripts/*.js
        UserScriptManager.shared.attachUserScripts(to: webViewConfiguration.userContentController)

        let darkBg = NSColor(calibratedRed: 0.07, green: 0.07, blue: 0.08, alpha: 1.0)
        self.webView = WKWebView(frame: .zero, configuration: webViewConfiguration)
        self.webView.autoresizingMask = [.width, .height]
        self.webView.setValue(false, forKey: "drawsBackground")
        self.webView.underPageBackgroundColor = darkBg
        self.webView.wantsLayer = true
        self.webView.layer?.backgroundColor = darkBg.cgColor

        super.init()

        self.scriptBridge.tab = self
        self.webView.navigationDelegate = self
        self.webView.uiDelegate = self
        setupObservers()

        if webView.responds(to: Selector(("_isPlayingAudio"))) {
            webView.addObserver(self, forKeyPath: "_isPlayingAudio", options: [.new], context: nil)
        }
    }

    deinit {
        webView.removeObserver(self, forKeyPath: "_isPlayingAudio")
    }

    public override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey : Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        if keyPath == "_isPlayingAudio" {
            let playing = (webView.value(forKey: "_isPlayingAudio") as? Bool) ?? false
            Task { @MainActor in
                self.setAudibleState(playing)
            }
        } else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }

    private func setupObservers() {
        // Observe document title changes (fires on static loads and dynamic SPA updates)
        webView.publisher(for: \.title)
            .compactMap { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] newTitle in
                guard let self = self else { return }
                if !newTitle.isEmpty {
                    self.title = newTitle
                    if let currentURL = self.webView.url {
                        let currentProfile = ProfileManager.shared.profiles.first(where: { $0.id == self.profileId })
                        if !(currentProfile?.isEphemeral ?? false) {
                            HistoryStore.shared.updateTitle(
                                url: currentURL,
                                title: newTitle,
                                profileId: self.profileId
                            )
                        }
                    }
                } else if let host = self.webView.url?.host {
                    self.title = host
                }
            }
            .store(in: &cancellables)

        // Observe URL changes (including pushState / client-side SPA routing)
        webView.publisher(for: \.url)
            .receive(on: RunLoop.main)
            .sink { [weak self] newURL in
                guard let self = self else { return }
                // Keep the failed URL pinned in the UI while the error page is displayed
                if self.failedURL == nil {
                    self.url = newURL
                    if self.title.isEmpty, let host = newURL?.host {
                        self.title = host
                    }
                }
                self.deriveFaviconURL(for: newURL)
                self.extractTopColor()
            }
            .store(in: &cancellables)

        // Observe loading state
        webView.publisher(for: \.isLoading)
            .receive(on: RunLoop.main)
            .sink { [weak self] loading in
                guard let self = self else { return }
                self.isLoading = loading
            }
            .store(in: &cancellables)

        // Observe estimated progress
        webView.publisher(for: \.estimatedProgress)
            .receive(on: RunLoop.main)
            .sink { [weak self] progress in
                guard let self = self else { return }
                self.estimatedProgress = progress
            }
            .store(in: &cancellables)

        // Observe back / forward navigation availability
        webView.publisher(for: \.canGoBack)
            .receive(on: RunLoop.main)
            .sink { [weak self] back in self?.canGoBack = back }
            .store(in: &cancellables)

        webView.publisher(for: \.canGoForward)
            .receive(on: RunLoop.main)
            .sink { [weak self] forward in self?.canGoForward = forward }
            .store(in: &cancellables)
    }

    // MARK: - WKNavigationDelegate

    public func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        preferences: WKWebpagePreferences,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy, WKWebpagePreferences) -> Void
    ) {
        // Session JS toggle (:js) and the persisted per-domain setting both apply
        let domainJS = DomainSettingsStore.shared.value(.javaScriptEnabled, forHost: navigationAction.request.url?.host)
        preferences.allowsContentJavaScript = self.isJavaScriptEnabled && domainJS

        if navigationAction.shouldPerformDownload {
            decisionHandler(.download, preferences)
            return
        }

        // Check for plaintext HTTP navigation
        if let targetURL = navigationAction.request.url,
           targetURL.scheme?.lowercased() == "http",
           targetURL.host?.lowercased() != "localhost",
           targetURL.host != "127.0.0.1",
           !bypassInsecureWarningURLs.contains(targetURL),
           !DomainSettingsStore.shared.value(.allowInsecureHttp, forHost: targetURL.host) {
            decisionHandler(.cancel, preferences)
            Task { @MainActor in
                let allow = await PluginRegistry.shared.confirm(
                    prompt: "INSECURE",
                    promptIcon: "exclamationmark.triangle.fill",
                    message: "Connection to \(targetURL.host ?? "") is unencrypted (HTTP). Proceed?",
                    defaultYes: false
                )
                if allow {
                    self.bypassInsecureWarningURLs.insert(targetURL)
                    self.load(url: targetURL)
                }
            }
            return
        }

        decisionHandler(.allow, preferences)
    }

    public func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void
    ) {
        // Intercept gateway / server errors on the main frame and render the zen error page
        if navigationResponse.isForMainFrame,
           let http = navigationResponse.response as? HTTPURLResponse,
           (500...599).contains(http.statusCode),
           let failed = http.url {
            decisionHandler(.cancel)
            let content = ErrorPageTemplate.content(forHTTPStatus: http.statusCode)
            showErrorPage(for: failed, code: content.code, headline: content.headline, message: content.message)
            return
        }

        if navigationResponse.canShowMIMEType {
            decisionHandler(.allow)
            return
        }

        let filename = navigationResponse.response.suggestedFilename ?? "download"
        let length = navigationResponse.response.expectedContentLength
        let sizeInfo = length > 0 ? " (\(ByteCountFormatter.string(fromByteCount: length, countStyle: .file)))" : ""

        // Trusted domains can skip the download confirmation entirely
        if DomainSettingsStore.shared.value(.skipDownloadConfirmation, forHost: navigationResponse.response.url?.host) {
            decisionHandler(.download)
            return
        }

        Task { @MainActor in
            let allow = await PluginRegistry.shared.confirm(
                prompt: "DOWNLOAD",
                promptIcon: "arrow.down.circle.fill",
                message: "Download \(filename)\(sizeInfo)?",
                defaultYes: true
            )
            if allow {
                decisionHandler(.download)
            } else {
                decisionHandler(.cancel)
            }
        }
    }

    public func webView(
        _ webView: WKWebView,
        navigationResponse: WKNavigationResponse,
        didBecome download: WKDownload
    ) {
        DownloadManager.shared.track(download, suggestedFilename: navigationResponse.response.suggestedFilename ?? "download")
    }

    public func webView(
        _ webView: WKWebView,
        navigationAction: WKNavigationAction,
        didBecome download: WKDownload
    ) {
        DownloadManager.shared.track(download, suggestedFilename: download.originalRequest?.url?.lastPathComponent ?? "download")
    }

    public func webView(
        _ webView: WKWebView,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @MainActor @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            self.currentServerTrust = trust
        }
        completionHandler(.performDefaultHandling, nil)
    }

    public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        self.isLoading = true
        self.provisionalTargetURL = webView.url
        if let host = webView.url?.host {
            if self.title.isEmpty {
                self.title = host
            }
        }
    }

    public func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        if let newTitle = webView.title, !newTitle.isEmpty {
            self.title = newTitle
        }
        if failedURL == nil {
            self.url = webView.url
        }
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        self.isLoading = false
        if let newTitle = webView.title, !newTitle.isEmpty {
            self.title = newTitle
        }
        self.url = webView.url

        if let currentURL = webView.url {
            let currentProfile = ProfileManager.shared.profiles.first(where: { $0.id == profileId })
            if !(currentProfile?.isEphemeral ?? false) {
                HistoryStore.shared.recordVisit(
                    url: currentURL,
                    title: self.title,
                    profileId: profileId,
                    isTyped: false
                )
            }
        }

        // Per-domain auto-mute applies on every load; re-muting after a manual
        // unmute on the next navigation is the predictable behavior
        if DomainSettingsStore.shared.value(.muteAudio, forHost: webView.url?.host), !isMuted {
            toggleMute(enable: true)
            PluginRegistry.shared.showToast(NotificationToast(message: "Muted (domain setting)", duration: 3.0))
        }

        extractTopColor()
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        self.isLoading = false
        handleLoadFailure(error as NSError)
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        self.isLoading = false
        handleLoadFailure(error as NSError)
    }

    /// Renders the zen error fallback page for main-frame load failures.
    /// Cancels (-999) and subframe/resource failures are ignored.
    private func handleLoadFailure(_ error: NSError) {
        if error.code == NSURLErrorCancelled { return }
        // Policy-change interruptions fire after our own .cancel decisions (5xx error
        // page, download conversion) — the error page is already rendered by then
        if error.domain == "WebKitErrorDomain" && error.code == 102 { return }

        let failingURL = error.userInfo[NSURLErrorFailingURLErrorKey] as? URL

        let isMainFrame = failingURL == nil
            || failingURL == lastRequestedURL
            || failingURL == provisionalTargetURL
            || failingURL == webView.url
            || failingURL == self.url
        guard isMainFrame, let target = failingURL ?? self.url else { return }
        guard target.scheme?.lowercased() != "vimzen" else { return }

        let content = ErrorPageTemplate.content(forError: error)
        showErrorPage(for: target, code: content.code, headline: content.headline, message: content.message)
    }

    private func showErrorPage(for failed: URL, code: String, headline: String, message: String) {
        self.failedURL = failed
        isNewTabScratchpad = false
        customTopColor = nil
        detectedTopColor = nil
        isMuted = false
        isAudible = false
        isPlayingMedia = false
        title = "\(code) · \(headline)"
        url = failed
        topColor = NSColor(calibratedRed: 0.07, green: 0.07, blue: 0.08, alpha: 1.0)
        webView.loadHTMLString(
            ErrorPageTemplate.html(code: code, headline: headline, message: message, failedURL: failed),
            baseURL: failed
        )
    }

    // MARK: - Navigation & Actions

    private func deriveFaviconURL(for pageURL: URL?) {
        guard let pageURL = pageURL,
              let scheme = pageURL.scheme,
              let host = pageURL.host else {
            faviconURL = nil
            return
        }
        faviconURL = URL(string: "\(scheme)://\(host)/favicon.ico")
    }

    public func load(url: URL) {
        failedURL = nil
        if url.scheme?.lowercased() == "vimzen" {
            if url.host?.lowercased() == "help" {
                loadHelpTemplate()
                return
            } else if url.host?.lowercased() == "newtab" {
                loadNewTabTemplate()
                return
            }
        }

        isNewTabScratchpad = false
        customTopColor = nil
        detectedTopColor = nil
        topColor = nil
        isMuted = false
        isAudible = false
        isPlayingMedia = false

        // Pin the intended target so provisional failures (e.g. connection refused)
        // can be attributed to the main frame even if webView.url hasn't updated yet
        provisionalTargetURL = url
        lastRequestedURL = url

        let request = URLRequest(url: url)
        webView.load(request)
    }

    public func loadHelpTemplate() {
        isNewTabScratchpad = false
        failedURL = nil
        title = "Vimzen Help"
        url = URL(string: "vimzen://help")
        customTopColor = nil
        detectedTopColor = nil
        isMuted = false
        isAudible = false
        isPlayingMedia = false
        topColor = NSColor(calibratedRed: 0.07, green: 0.07, blue: 0.08, alpha: 1.0)
        webView.loadHTMLString(HelpPageTemplate.html(), baseURL: URL(string: "vimzen://help"))
    }

    public func setCustomTopColor(_ color: NSColor?) {
        customTopColor = color
        updateEffectiveTopColor()
    }

    private func updateEffectiveTopColor() {
        if let custom = customTopColor {
            topColor = custom
        } else if let detected = detectedTopColor {
            topColor = detected
        } else if isNewTabScratchpad {
            topColor = NSColor(calibratedRed: 0.07, green: 0.07, blue: 0.08, alpha: 1.0)
        } else {
            topColor = nil
        }
    }

    public func loadNewTabTemplate() {
        isNewTabScratchpad = true
        failedURL = nil
        title = "New Tab"
        url = URL(string: "vimzen://newtab")
        customTopColor = nil
        detectedTopColor = nil
        isMuted = false
        isAudible = false
        isPlayingMedia = false
        updateEffectiveTopColor()
        let savedNotes = ScratchpadStore.loadNotes(for: profileId)
        webView.loadHTMLString(NewTabTemplate.html(initialNotes: savedNotes), baseURL: URL(string: "vimzen://newtab"))
    }

    public func extractTopColor() {
        if isNewTabScratchpad {
            updateEffectiveTopColor()
            return
        }

        let script = """
        (function() {
            var meta = document.querySelector('meta[name="theme-color"]');
            if (meta && meta.content) return meta.content;
            if (document.body) {
                var bg = window.getComputedStyle(document.body).backgroundColor;
                if (bg && bg !== 'rgba(0, 0, 0, 0)' && bg !== 'transparent') return bg;
            }
            if (document.documentElement) {
                var htmlBg = window.getComputedStyle(document.documentElement).backgroundColor;
                if (htmlBg && htmlBg !== 'rgba(0, 0, 0, 0)' && htmlBg !== 'transparent') return htmlBg;
            }
            return null;
        })();
        """

        webView.evaluateJavaScript(script) { [weak self] result, error in
            guard let self = self else { return }
            if let colorStr = result as? String, let parsed = ColorParser.parse(colorStr) {
                self.detectedTopColor = parsed
            } else {
                self.detectedTopColor = nil
            }
            self.updateEffectiveTopColor()
        }
    }

    public func focusEditorIfNewTab() {
        if isNewTabScratchpad {
            webView.evaluateJavaScript("document.getElementById('pad')?.focus();", completionHandler: nil)
        }
    }

    public func blurEditorIfNewTab() {
        if isNewTabScratchpad {
            webView.evaluateJavaScript("document.getElementById('pad')?.blur();", completionHandler: nil)
        }
    }

    public func scrollBy(dx: CGFloat, dy: CGFloat) {
        let script = "window.scrollBy({ left: \(dx), top: \(dy), behavior: 'instant' });"
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    public func scrollToTop() {
        webView.evaluateJavaScript("window.scrollTo(0, 0);", completionHandler: nil)
    }

    public func scrollToBottom() {
        webView.evaluateJavaScript("window.scrollTo(0, document.body.scrollHeight);", completionHandler: nil)
    }

    public func reload() {
        // Re-attempt the original URL when the error fallback page is displayed
        if let failed = failedURL {
            load(url: failed)
        } else {
            webView.reload()
        }
    }

    public func reloadFromOrigin() {
        if let failed = failedURL {
            load(url: failed)
        } else {
            webView.reloadFromOrigin()
        }
    }

    public func goBack(count: Int = 1) {
        if webView.canGoBack {
            let backList = webView.backForwardList.backList
            if count <= 1 {
                webView.goBack()
            } else if !backList.isEmpty {
                let targetIndex = max(0, backList.count - count)
                webView.go(to: backList[targetIndex])
            }
        } else {
            PluginRegistry.shared.showToast(
                NotificationToast(message: "Already at oldest page in history", duration: 1.5)
            )
        }
    }

    public func goForward(count: Int = 1) {
        if webView.canGoForward {
            let forwardList = webView.backForwardList.forwardList
            if count <= 1 {
                webView.goForward()
            } else if !forwardList.isEmpty {
                let targetIndex = min(forwardList.count - 1, count - 1)
                webView.go(to: forwardList[targetIndex])
            }
        } else {
            PluginRegistry.shared.showToast(
                NotificationToast(message: "Already at newest page in history", duration: 1.5)
            )
        }
    }

    // MARK: - Find in Page (Vim / Search)

    public func findInPage(
        _ query: String,
        forward: Bool = true,
        notifyIfNotFound: Bool = false,
        onCountUpdated: (@MainActor (Int, Int) -> Void)? = nil
    ) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            currentSearchIndex = 0
            totalSearchMatches = 0
            onCountUpdated?(0, 0)
            return
        }

        let isNewPattern = (trimmed.lowercased() != lastSearchQuery.lowercased())
        lastSearchQuery = trimmed

        let config = WKFindConfiguration()
        config.backwards = !forward
        config.wraps = true
        config.caseSensitive = false

        webView.find(trimmed, configuration: config) { [weak self] result in
            guard let self = self else { return }
            if !result.matchFound {
                self.currentSearchIndex = 0
                self.totalSearchMatches = 0
                onCountUpdated?(0, 0)
                if notifyIfNotFound {
                    PluginRegistry.shared.showToast(
                        NotificationToast(message: "Pattern not found: \(trimmed)", duration: 1.5)
                    )
                }
            } else {
                if isNewPattern {
                    self.countMatchesInDOM(trimmed) { [weak self] total in
                        guard let self = self else { return }
                        self.totalSearchMatches = total
                        self.currentSearchIndex = total > 0 ? 1 : 0
                        onCountUpdated?(self.currentSearchIndex, self.totalSearchMatches)
                    }
                } else {
                    if self.totalSearchMatches > 0 {
                        if forward {
                            self.currentSearchIndex = (self.currentSearchIndex % self.totalSearchMatches) + 1
                        } else {
                            self.currentSearchIndex = ((self.currentSearchIndex - 2 + self.totalSearchMatches) % self.totalSearchMatches) + 1
                        }
                    }
                    onCountUpdated?(self.currentSearchIndex, self.totalSearchMatches)
                }
            }
        }
    }

    private func countMatchesInDOM(_ query: String, completion: @escaping @MainActor (Int) -> Void) {
        let escaped = query
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: " ")
        let script = """
        (function() {
            try {
                if (!document.body) return 0;
                var text = document.body.innerText || "";
                var re = new RegExp('\(escaped)', 'gi');
                var m = text.match(re);
                return m ? m.length : 0;
            } catch(e) {
                return 0;
            }
        })();
        """
        webView.evaluateJavaScript(script) { result, _ in
            let count = (result as? Int) ?? (result as? NSNumber)?.intValue ?? 0
            Task { @MainActor in
                completion(count)
            }
        }
    }

    public func findNext(count: Int = 1) {
        guard !lastSearchQuery.isEmpty else {
            PluginRegistry.shared.showToast(
                NotificationToast(message: "No previous search pattern (press / to search)", duration: 2.0)
            )
            return
        }
        for _ in 0..<max(1, count) {
            findInPage(lastSearchQuery, forward: true, notifyIfNotFound: true) { [weak self] current, total in
                guard let self = self else { return }
                if total > 0 {
                    PluginRegistry.shared.showToast(
                        NotificationToast(message: "[\(current)/\(total)]  /\(self.lastSearchQuery)", duration: 1.5)
                    )
                }
            }
        }
    }

    public func findPrevious(count: Int = 1) {
        guard !lastSearchQuery.isEmpty else {
            PluginRegistry.shared.showToast(
                NotificationToast(message: "No previous search pattern (press / to search)", duration: 2.0)
            )
            return
        }
        for _ in 0..<max(1, count) {
            findInPage(lastSearchQuery, forward: false, notifyIfNotFound: true) { [weak self] current, total in
                guard let self = self else { return }
                if total > 0 {
                    PluginRegistry.shared.showToast(
                        NotificationToast(message: "[\(current)/\(total)]  /\(self.lastSearchQuery)", duration: 1.5)
                    )
                }
            }
        }
    }

    public func clearFindMatches() {
        webView.evaluateJavaScript("window.getSelection()?.removeAllRanges();", completionHandler: nil)
    }

    public func updateMediaState(isAudible: Bool, isPlaying: Bool, isMuted: Bool, mediaKind: String) {
        self.mediaKind = mediaKind
        setAudibleState(isAudible || isPlaying)
    }

    public func setAudibleState(_ active: Bool) {
        if active {
            silenceDebounceTask?.cancel()
            silenceDebounceTask = nil
            if isMuted {
                isMuted = false
            }
            if !self.isAudible {
                self.isAudible = true
                self.isPlayingMedia = true
            }
            self.lastAudibleAt = Date()
        } else {
            // Apply 1.2s silence hold timer to absorb buffer transitions and prevent flickering
            if self.isAudible && silenceDebounceTask == nil {
                silenceDebounceTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                    guard !Task.isCancelled, let self = self else { return }
                    self.isAudible = false
                    self.isPlayingMedia = false
                    self.silenceDebounceTask = nil
                }
            }
        }
    }

    public func toggleMute(enable: Bool? = nil) {
        let targetMute = enable ?? !isMuted
        isMuted = targetMute
        if targetMute {
            silenceDebounceTask?.cancel()
            silenceDebounceTask = nil
            isAudible = false
            isPlayingMedia = false
        }

        // 1. Try native WebKit muting SPI
        let sel = Selector(("_setAllMediaMuted:"))
        if webView.responds(to: sel) {
            _ = webView.perform(sel, with: NSNumber(value: targetMute))
        }

        // 2. Also run DOM & Web Audio JS muting
        let script = "if (window.vimzenMuteMedia) { window.vimzenMuteMedia(\(targetMute)); }"
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    public func toggleJavaScript(enable: Bool? = nil) {
        if let enable = enable {
            isJavaScriptEnabled = enable
        } else {
            isJavaScriptEnabled.toggle()
        }
        webView.reload()
    }

    public func certificateSummary() -> String {
        guard let url = webView.url else {
            return "No page loaded"
        }
        guard url.scheme?.lowercased() == "https" else {
            return "⚠️ Insecure connection (\(url.scheme?.uppercased() ?? "HTTP"))"
        }

        guard let trust = currentServerTrust ?? webView.serverTrust else {
            return "🔒 TLS Active (\(url.host ?? "domain"))"
        }

        var error: CFError?
        let isTrusted = SecTrustEvaluateWithError(trust, &error)

        var details: [String] = []
        if isTrusted {
            details.append("🔒 Trusted TLS")
        } else {
            details.append("⚠️ Untrusted Certificate")
        }

        if let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate], let cert = chain.first {
            let summary = SecCertificateCopySubjectSummary(cert) as String? ?? (url.host ?? "Certificate")
            details.append(summary)
        }

        return details.joined(separator: " · ")
    }

    public func exportPDF() async throws -> URL {
        let pdfData = try await webView.pdf()
        let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads", isDirectory: true)

        let rawTitle = (title.isEmpty ? (url?.host ?? "Document") : title)
        let safeTitle = rawTitle.replacingOccurrences(of: "[^a-zA-Z0-9._-]", with: "_", options: .regularExpression)
        let filename = safeTitle.isEmpty ? "Page.pdf" : "\(safeTitle).pdf"

        var targetURL = downloadsDir.appendingPathComponent(filename)
        let fm = FileManager.default
        let baseName = (filename as NSString).deletingPathExtension
        var index = 1
        while fm.fileExists(atPath: targetURL.path) {
            targetURL = downloadsDir.appendingPathComponent("\(baseName) (\(index)).pdf")
            index += 1
        }

        try pdfData.write(to: targetURL)
        return targetURL
    }
}

// MARK: - WKUIDelegate (popups & JavaScript dialogs)

extension Tab: WKUIDelegate {

    /// window.open() and target="_blank" both funnel here. Without this method
    /// WKWebView silently drops them. Popups open as regular tabs — keyboard-first
    /// browsers have no separate popup windows — and the new tab loads the URL
    /// itself, so we return nil (no WebKit-created web view).
    public func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard let url = navigationAction.request.url else { return nil }

        // Domains marked popupsRequireConfirmation get a y/N gate keyed off the
        // *source* page's host; while one confirm is pending further popups from
        // it are dropped silently (no confirm-stacking from a popup loop)
        let sourceHost = webView.url?.host
        if DomainSettingsStore.shared.value(.popupsRequireConfirmation, forHost: sourceHost) {
            if popupConfirmPending { return nil }
            popupConfirmPending = true
            Task { @MainActor in
                let allow = await PluginRegistry.shared.confirm(
                    prompt: "POPUP",
                    promptIcon: "macwindow.badge.plus",
                    message: "Allow popup to \(url.host ?? url.absoluteString)?",
                    defaultYes: false
                )
                self.popupConfirmPending = false
                if allow {
                    self.tabManager?.createTab(url: url, activate: true)
                }
            }
            return nil
        }

        tabManager?.createTab(url: url, activate: true)
        return nil
    }

    /// window.close() from a script-opened page closes its tab.
    public func webViewDidClose(_ webView: WKWebView) {
        tabManager?.closeTab(id: id)
    }

    public func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable () -> Void
    ) {
        let alert = makeDialogAlert(message: message, webView: webView)
        alert.addButton(withTitle: "OK")
        alert.runModal()
        completionHandler()
    }

    public func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable (Bool) -> Void
    ) {
        let alert = makeDialogAlert(message: message, webView: webView)
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.last?.keyEquivalent = "\u{1b}" // Escape = Cancel
        completionHandler(alert.runModal() == .alertFirstButtonReturn)
    }

    public func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable (String?) -> Void
    ) {
        let alert = makeDialogAlert(message: prompt, webView: webView)
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.last?.keyEquivalent = "\u{1b}" // Escape = Cancel

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = defaultText ?? ""
        alert.accessoryView = field
        alert.layout()
        alert.window.makeFirstResponder(field)

        let accepted = alert.runModal() == .alertFirstButtonReturn
        completionHandler(accepted ? field.stringValue : nil)
    }

    /// Consistent, minimal JS dialog chrome; the origin host is shown as context
    /// so the page text can't impersonate a system message.
    private func makeDialogAlert(message: String, webView: WKWebView) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = message
        if let host = webView.url?.host, !host.isEmpty {
            alert.informativeText = host
        }
        return alert
    }
}
