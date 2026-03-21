//
//  UnixSocketProtocol.swift
//  Rayee
//
//  Routes HTTP requests through a Unix domain socket instead of TCP.
//  This avoids interfering with VPNs (e.g. Cloudflare WARP) since Unix
//  sockets bypass the network stack entirely.
//

import Foundation

/// URLProtocol that intercepts HTTP requests to the server URL
/// and routes them through a Unix domain socket.
class UnixSocketProtocol: URLProtocol {
    /// Flag to prevent re-entry
    private static let handledKey = "UnixSocketHandled"

    /// Track cancellation
    private var isCancelled = false

    // MARK: - URLProtocol Overrides

    override class func canInit(with request: URLRequest) -> Bool {
        guard let url = request.url,
              url.host == "127.0.0.1",
              url.port == 8765 else { return false }
        // Don't handle if already processed
        return property(forKey: handledKey, in: request) == nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            performRequest()
        }
    }

    override func stopLoading() {
        isCancelled = true
    }

    // MARK: - Socket Communication

    private func performRequest() {
        let socketPath = Config.serverSocketPath

        // Create Unix domain socket
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            reportError(.cannotConnectToHost)
            return
        }

        // Set timeouts to match the URLRequest timeout
        let timeoutSec = max(Int(request.timeoutInterval), 5)
        var timeout = timeval(tv_sec: timeoutSec, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        // Connect to socket file
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &addr.sun_path.0) { ptr in
            _ = socketPath.withCString { strncpy(ptr, $0, 104) }
        }

        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard connectResult == 0 else {
            Darwin.close(fd)
            reportError(.cannotConnectToHost)
            return
        }

        // Build HTTP request text
        let httpText = buildHTTPText()
        guard var requestData = httpText.data(using: .utf8) else {
            Darwin.close(fd)
            reportError(.cannotParseResponse)
            return
        }

        // Append body if present
        if let body = request.httpBody {
            requestData.append(body)
        }

        // Send request
        let sendOK = requestData.withUnsafeBytes { ptr -> Bool in
            var sent = 0
            let total = requestData.count
            while sent < total {
                let n = send(fd, ptr.baseAddress! + sent, total - sent, 0)
                if n <= 0 { return false }
                sent += n
            }
            return true
        }

        guard sendOK else {
            Darwin.close(fd)
            reportError(.networkConnectionLost)
            return
        }

        // Read response until connection closes
        var responseData = Data()
        let bufSize = 65536
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: bufSize)
        defer { buf.deallocate() }

        while !isCancelled {
            let n = recv(fd, buf, bufSize, 0)
            if n <= 0 { break }
            responseData.append(buf, count: n)
        }

        Darwin.close(fd)

        guard !isCancelled else { return }

        // Parse response using CFHTTPMessage (handles chunked encoding, etc.)
        let cfMsg = CFHTTPMessageCreateEmpty(kCFAllocatorDefault, false).takeRetainedValue()
        responseData.withUnsafeBytes { ptr in
            guard let base = ptr.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            CFHTTPMessageAppendBytes(cfMsg, base, responseData.count)
        }

        guard CFHTTPMessageIsHeaderComplete(cfMsg) else {
            reportError(.cannotParseResponse)
            return
        }

        let statusCode = CFHTTPMessageGetResponseStatusCode(cfMsg)
        let body = (CFHTTPMessageCopyBody(cfMsg)?.takeRetainedValue()) as Data? ?? Data()
        let headers = CFHTTPMessageCopyAllHeaderFields(cfMsg)?.takeRetainedValue() as? [String: String] ?? [:]

        guard let httpResponse = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        ) else {
            reportError(.cannotParseResponse)
            return
        }

        client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    // MARK: - Helpers

    /// Build a raw HTTP/1.1 request string
    private func buildHTTPText() -> String {
        let url = request.url!
        let method = request.httpMethod ?? "GET"
        var path = url.path
        if path.isEmpty { path = "/" }
        if let query = url.query { path += "?\(query)" }

        var msg = "\(method) \(path) HTTP/1.1\r\n"
        msg += "Host: localhost\r\n"
        msg += "Connection: close\r\n"

        for (key, value) in request.allHTTPHeaderFields ?? [:] {
            let k = key.lowercased()
            if k != "host" && k != "connection" {
                msg += "\(key): \(value)\r\n"
            }
        }

        if let body = request.httpBody {
            msg += "Content-Length: \(body.count)\r\n"
        }

        msg += "\r\n"
        return msg
    }

    private func reportError(_ code: URLError.Code) {
        client?.urlProtocol(self, didFailWithError: URLError(code))
    }
}
