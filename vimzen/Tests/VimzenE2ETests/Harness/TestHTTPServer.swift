import Foundation
import Network

struct FixtureRequest: Sendable {
    let method: String
    let path: String
    let headers: [String: String] // lowercased header names

    var cookieHeader: String { headers["cookie"] ?? "" }
}

struct FixtureResponse: Sendable {
    var status: Int
    var headers: [String: String]
    var body: String

    static func html(_ status: Int = 200, title: String, extraHeaders: [String: String] = [:], _ body: String) -> FixtureResponse {
        FixtureResponse(
            status: status,
            headers: ["Content-Type": "text/html; charset=utf-8"].merging(extraHeaders) { _, new in new },
            body: "<!DOCTYPE html><html><head><meta charset=\"utf-8\"><title>\(title)</title></head><body>\(body)</body></html>"
        )
    }
}

/// Minimal HTTP/1.1 fixture server for E2E tests, built on Network.framework.
/// Sends `Connection: close` after each response; one request per connection.
final class TestHTTPServer: @unchecked Sendable {
    private let lock = NSLock()
    private var routes: [String: (FixtureRequest) -> FixtureResponse] = [:]
    private var requestLog: [FixtureRequest] = []
    private var listener: NWListener?

    private(set) var port: UInt16 = 0

    var baseURL: String { "http://127.0.0.1:\(port)" }
    /// A non-localhost address of this machine — not in Vimzen's plaintext-HTTP
    /// prompt exemption list, so it exercises the INSECURE gate. Prefers the LAN
    /// address (proven to work in WKWebView); falls back to the `localhost.` FQDN
    /// form, which the system resolver also maps to loopback.
    var altBaseURL: String {
        if let lan = TestHTTPServer.lanIPAddress() {
            return "http://\(lan):\(port)"
        }
        return "http://localhost.:\(port)"
    }

    /// Allocates an ephemeral port, then immediately releases it so nothing is
    /// listening — for connection-refused tests. Ephemeral ports (49152+) never
    /// overlap WebKit's restricted-port list, so the load genuinely attempts and
    /// fails with NSURLErrorCannotConnectToHost (-1004).
    static func allocateClosedPort() throws -> UInt16 {
        final class PortBox: @unchecked Sendable {
            private let lock = NSLock()
            private var _value: UInt16 = 0
            var value: UInt16 {
                get { lock.lock(); defer { lock.unlock() }; return _value }
                set { lock.lock(); defer { lock.unlock() }; _value = newValue }
            }
        }
        let box = PortBox()
        let listener = try NWListener(using: .tcp, on: .any)
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { state in
            if case .ready = state {
                box.value = listener.port?.rawValue ?? 0
                ready.signal()
            }
        }
        // NWListener never becomes ready (EINVAL) unless a connection handler is set
        listener.newConnectionHandler = { connection in connection.cancel() }
        listener.start(queue: DispatchQueue(label: "e2e.port.alloc"))
        defer { listener.cancel() }
        if ready.wait(timeout: .now() + 5) == .timedOut || box.value == 0 {
            throw NSError(domain: "E2E", code: 5, userInfo: [NSLocalizedDescriptionKey: "could not allocate a closed port"])
        }
        return box.value
    }

    /// First IPv4 address of en0 (Wi-Fi), e.g. "192.168.29.226".
    static func lanIPAddress() -> String? {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let first = interfaces else { return nil }
        defer { freeifaddrs(interfaces) }

        var current: UnsafeMutablePointer<ifaddrs>? = first
        while let iface = current {
            let name = String(cString: iface.pointee.ifa_name)
            if name == "en0",
               let addr = iface.pointee.ifa_addr,
               addr.pointee.sa_family == UInt8(AF_INET) {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                    return String(cString: host)
                }
            }
            current = iface.pointee.ifa_next
        }
        return nil
    }

    func route(_ path: String, handler: @escaping @Sendable (FixtureRequest) -> FixtureResponse) {
        lock.lock()
        routes[path] = handler
        lock.unlock()
    }

    func start() throws {
        let listener = try NWListener(using: .tcp, on: .any)
        self.listener = listener

        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { [weak self] state in
            if case .ready = state {
                self?.lock.lock()
                self?.port = listener.port?.rawValue ?? 0
                self?.lock.unlock()
                ready.signal()
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection: connection)
        }
        listener.start(queue: DispatchQueue(label: "e2e.http.listener"))
        if ready.wait(timeout: .now() + 5) == .timedOut {
            throw NSError(domain: "E2E", code: 1, userInfo: [NSLocalizedDescriptionKey: "Test server failed to start"])
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - Request log

    func hits(_ pathPrefix: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return requestLog.filter { $0.path.hasPrefix(pathPrefix) }.count
    }

    func requests(to pathPrefix: String) -> [FixtureRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requestLog.filter { $0.path.hasPrefix(pathPrefix) }
    }

    func clearLog() {
        lock.lock()
        requestLog.removeAll()
        lock.unlock()
    }

    // MARK: - Connection handling

    private func handle(connection: NWConnection) {
        connection.start(queue: DispatchQueue(label: "e2e.http.conn"))
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, _ in
            guard let self = self else { connection.cancel(); return }
            var buffer = buffer
            if let data = data { buffer.append(data) }
            if let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let headerData = buffer.subdata(in: 0..<headerEnd.lowerBound)
                let request = self.parse(headerData)
                self.lock.lock()
                self.requestLog.append(request)
                let handler = self.routes[request.path]
                self.lock.unlock()
                let response = handler?(request) ?? FixtureResponse(
                    status: 404,
                    headers: ["Content-Type": "text/plain"],
                    body: "not found"
                )
                self.write(response, on: connection)
            } else if isComplete {
                connection.cancel()
            } else {
                self.receive(on: connection, buffer: buffer)
            }
        }
    }

    private func parse(_ headerData: Data) -> FixtureRequest {
        let text = String(decoding: headerData, as: UTF8.self)
        var lines = text.components(separatedBy: "\r\n")
        let requestLine = lines.isEmpty ? "" : lines.removeFirst()
        let parts = requestLine.components(separatedBy: " ")
        let method = parts.count > 0 ? parts[0] : "GET"
        let path = parts.count > 1 ? parts[1] : "/"
        var headers: [String: String] = [:]
        for line in lines {
            guard let sep = line.firstIndex(of: ":") else { continue }
            let name = line[..<sep].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: sep)...].trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }
        return FixtureRequest(method: method, path: path, headers: headers)
    }

    private func write(_ response: FixtureResponse, on connection: NWConnection) {
        let statusText: [Int: String] = [
            200: "OK", 302: "Found", 404: "Not Found",
            500: "Internal Server Error", 502: "Bad Gateway",
            503: "Service Unavailable", 504: "Gateway Timeout"
        ]
        var head = "HTTP/1.1 \(response.status) \(statusText[response.status] ?? "Status")\r\n"
        for (name, value) in response.headers {
            head += "\(name): \(value)\r\n"
        }
        head += "Content-Length: \(response.body.utf8.count)\r\n"
        head += "Connection: close\r\n\r\n"
        var payload = Data(head.utf8)
        payload.append(Data(response.body.utf8))
        connection.send(content: payload, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

// MARK: - Default fixture pages

extension TestHTTPServer {
    func registerDefaultFixtures() {
        route("/") { _ in
            .html(title: "Home · E2E", "<p>home-root-marker</p>")
        }
        route("/alpha") { _ in
            .html(title: "Alpha Page", "<p>alpha-marker e2efindtoken middle e2efindtoken</p>")
        }
        route("/beta") { _ in
            .html(title: "Beta Page", "<p>beta-marker</p>")
        }
        route("/gamma") { _ in
            .html(title: "Gamma Page", "<p>gamma-marker</p>")
        }
        route("/tall") { _ in
            .html(title: "Tall Page", """
            <div style="height:20000px">tall-top-marker</div>
            <script>
            window.addEventListener('scroll', function() {
                document.title = 'scrolled:' + Math.round(window.scrollY);
            });
            </script>
            """)
        }
        route("/form") { _ in
            .html(title: "Form Page", """
            <input id="q" type="text" autofocus>
            <script>
            var q = document.getElementById('q');
            window.addEventListener('load', function() { q.focus(); });
            q.addEventListener('input', function() { document.title = 'typed:' + q.value; });
            </script>
            """)
        }
        route("/set-cookie") { _ in
            .html(
                title: "Cookie Setter",
                extraHeaders: ["Set-Cookie": "e2e_token=present; Path=/; SameSite=Lax"],
                "<p>cookie-set-marker</p>"
            )
        }
        route("/echo-cookie") { request in
            .html(title: "Cookie Echo", "<p>cookies:[\(request.cookieHeader)]</p>")
        }
        route("/502") { _ in
            .html(502, title: "Upstream Broken", "<p>upstream exploded</p>")
        }
        route("/503") { _ in
            .html(503, title: "Overloaded", "<p>try later</p>")
        }
        route("/redirect") { _ in
            FixtureResponse(status: 302, headers: ["Location": "/alpha"], body: "redirecting")
        }
        route("/download") { _ in
            FixtureResponse(
                status: 200,
                headers: [
                    "Content-Type": "application/octet-stream",
                    "Content-Disposition": "attachment; filename=\"e2e-fixture.bin\""
                ],
                body: "E2E-FIXTURE-PAYLOAD"
            )
        }
        route("/pdfpage") { _ in
            .html(title: "E2EPDFPAGE", "<p>pdf-marker</p>")
        }
        route("/popup") { _ in
            .html(title: "Popup Page", """
            <p>popup-opener-marker</p>
            <button onclick="window.open('/popup-target', '_blank', 'width=640,height=480')">window-open-btn</button>
            <a href="/popup-target" target="_blank">blank-link</a>
            <a href="/popup-target">plain-link</a>
            <button onclick="alert('e2e-alert-msg')">alert-btn</button>
            <button onclick="document.getElementById('r').textContent='confirm:'+confirm('e2e-confirm-msg')">confirm-btn</button>
            <button onclick="document.getElementById('r').textContent='prompt:'+prompt('e2e-prompt-msg','')">prompt-btn</button>
            <p id="r">result-idle</p>
            """)
        }
        route("/popup-target") { _ in
            .html(title: "Popup Target", "<p>popup-target-marker</p>")
        }
        // JS gate fixture: the marker says js-off until the script flips it to
        // js-on — <noscript> doesn't render under allowsContentJavaScript=false
        route("/js-check") { _ in
            .html(title: "JS Check", """
            <p>js-check-marker</p>
            <p id="jsstate">js-off-marker</p>
            <script>document.getElementById('jsstate').textContent = 'js-on-marker'</script>
            """)
        }
    }
}
