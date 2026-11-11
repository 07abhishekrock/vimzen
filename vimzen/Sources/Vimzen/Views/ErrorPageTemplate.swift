import Foundation

@MainActor
public enum ErrorPageTemplate {
    public static func html(code: String, headline: String, message: String, failedURL: URL?) -> String {
        let urlString = failedURL?.absoluteString ?? ""
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>\(escapeHTML(code)) · \(escapeHTML(headline))</title>
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
                .error-title {
                    font-size: 14px;
                    font-weight: 600;
                    color: #E78284;
                    letter-spacing: -0.2px;
                    margin-bottom: 16px;
                }
                .divider {
                    height: 1px;
                    background: #27272A;
                    width: 100%;
                }
                .body {
                    display: flex;
                    flex-direction: column;
                    gap: 10px;
                }
                .failed-url {
                    font-size: 13px;
                    color: #A1A1AA;
                    word-break: break-all;
                    line-height: 1.6;
                }
                .message {
                    font-size: 13px;
                    color: #71717A;
                    line-height: 1.6;
                }
                .hint {
                    font-size: 13px;
                    color: #52525B;
                    margin-top: 14px;
                    user-select: none;
                }
                .hint .kbd {
                    color: #5AC8FA;
                }
            </style>
        </head>
        <body>
            <div class="header-container">
                <div class="error-title">\(escapeHTML(code)) · \(escapeHTML(headline))</div>
                <div class="divider"></div>
            </div>
            <div class="body">
                <div class="failed-url">\(escapeHTML(urlString))</div>
                <div class="message">\(escapeHTML(message))</div>
                <div class="hint"><span class="kbd">:r</span> to reload</div>
            </div>
        </body>
        </html>
        """
    }

    public static func content(forHTTPStatus status: Int) -> (code: String, headline: String, message: String) {
        switch status {
        case 500:
            return ("500", "Internal Server Error", "The server encountered an internal error.")
        case 502:
            return ("502", "Bad Gateway", "The gateway received an invalid response from the upstream server.")
        case 503:
            return ("503", "Service Unavailable", "The service is temporarily overloaded or under maintenance.")
        case 504:
            return ("504", "Gateway Timeout", "The gateway timed out waiting for the upstream server.")
        case 505:
            return ("505", "HTTP Version Not Supported", "The server does not support the HTTP protocol version used.")
        default:
            return ("\(status)", "Server Error", "The server failed to respond. (HTTP \(status))")
        }
    }

    public static func content(forError error: NSError) -> (code: String, headline: String, message: String) {
        switch error.code {
        case NSURLErrorTimedOut:
            return ("ERR", "Timed Out", "The request timed out.")
        case NSURLErrorCannotFindHost:
            return ("ERR", "Server Not Found", "The server could not be found (DNS failure).")
        case NSURLErrorCannotConnectToHost:
            return ("ERR", "Connection Failed", "Could not connect to the server.")
        case NSURLErrorNetworkConnectionLost:
            return ("ERR", "Connection Lost", "The network connection was lost.")
        case NSURLErrorNotConnectedToInternet:
            return ("ERR", "No Internet", "You are not connected to the internet.")
        case NSURLErrorSecureConnectionFailed,
             NSURLErrorServerCertificateHasBadDate,
             NSURLErrorServerCertificateUntrusted,
             NSURLErrorServerCertificateHasUnknownRoot,
             NSURLErrorServerCertificateNotYetValid,
             NSURLErrorClientCertificateRejected,
             NSURLErrorClientCertificateRequired:
            return ("ERR", "Secure Connection Failed", "The secure connection to the server failed.")
        default:
            return ("ERR", "Load Failed", "The page failed to load. (\(error.localizedDescription))")
        }
    }

    private static func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
