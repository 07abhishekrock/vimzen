import AppKit
import WebKit
import Combine

@MainActor
public final class Tab: NSObject, Identifiable, ObservableObject, WKNavigationDelegate {
    public let id: UUID
    public let profileId: UUID
    public let webView: WKWebView

    @Published public var title: String = ""
    @Published public var url: URL?
    @Published public var faviconURL: URL?
    @Published public var isLoading: Bool = false
    @Published public var estimatedProgress: Double = 0.0
    @Published public var canGoBack: Bool = false
    @Published public var canGoForward: Bool = false
    public private(set) var lastActiveAt: Date = Date()

    public func markActive() {
        lastActiveAt = Date()
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
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        webViewConfiguration.defaultWebpagePreferences = preferences

        self.webView = WKWebView(frame: .zero, configuration: webViewConfiguration)
        self.webView.autoresizingMask = [.width, .height]

        super.init()

        self.webView.navigationDelegate = self
        setupObservers()
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
                self.url = newURL
                if self.title.isEmpty, let host = newURL?.host {
                    self.title = host
                }
                self.deriveFaviconURL(for: newURL)
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

    public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        self.isLoading = true
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
        self.url = webView.url
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        self.isLoading = false
        if let newTitle = webView.title, !newTitle.isEmpty {
            self.title = newTitle
        }
        self.url = webView.url
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        self.isLoading = false
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        self.isLoading = false
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
        let request = URLRequest(url: url)
        webView.load(request)
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
        webView.reload()
    }

    public func reloadFromOrigin() {
        webView.reloadFromOrigin()
    }

    public func goBack(count: Int = 1) {
        let backList = webView.backForwardList.backList
        if count <= 1 {
            if webView.canGoBack {
                webView.goBack()
            }
        } else if !backList.isEmpty {
            let targetIndex = max(0, backList.count - count)
            webView.go(to: backList[targetIndex])
        }
    }

    public func goForward(count: Int = 1) {
        let forwardList = webView.backForwardList.forwardList
        if count <= 1 {
            if webView.canGoForward {
                webView.goForward()
            }
        } else if !forwardList.isEmpty {
            let targetIndex = min(forwardList.count - 1, count - 1)
            webView.go(to: forwardList[targetIndex])
        }
    }
}
