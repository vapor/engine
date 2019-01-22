import NetKit
import XCTest

class HTTPTests: XCTestCase {
    func testCookieParse() throws {
        /// from https://developer.mozilla.org/en-US/docs/Web/HTTP/Cookies
        guard let (name, value) = HTTPCookieValue.parse("id=a3fWa; Expires=Wed, 21 Oct 2015 07:28:00 GMT; Secure; HttpOnly") else {
            throw HTTPError(identifier: "cookie", reason: "Could not parse test cookie")
        }
        XCTAssertEqual(name, "id")
        XCTAssertEqual(value.string, "a3fWa")
        XCTAssertEqual(value.expires, Date(rfc1123: "Wed, 21 Oct 2015 07:28:00 GMT"))
        XCTAssertEqual(value.isSecure, true)
        XCTAssertEqual(value.isHTTPOnly, true)
        
        guard let cookie: (name: String, value: HTTPCookieValue) = HTTPCookieValue.parse("vapor=; Secure; HttpOnly") else {
            throw HTTPError(identifier: "cookie", reason: "Could not parse test cookie")
        }
        XCTAssertEqual(cookie.name, "vapor")
        XCTAssertEqual(cookie.value.string, "")
        XCTAssertEqual(cookie.value.isSecure, true)
        XCTAssertEqual(cookie.value.isHTTPOnly, true)
    }
    
    func testCookieIsSerializedCorrectly() throws {
        var httpReq = HTTPRequest(method: .GET, url: "/")

        guard let (name, value) = HTTPCookieValue.parse("id=value; Expires=Wed, 21 Oct 2015 07:28:00 GMT; Secure; HttpOnly") else {
            throw HTTPError(identifier: "cookie", reason: "Could not parse test cookie")
        }
        
        httpReq.cookies = HTTPCookies(dictionaryLiteral: (name, value))
        
        XCTAssertEqual(httpReq.headers.firstValue(name: .cookie), "id=value")
    }

    func testAcceptHeader() throws {
        let httpReq = HTTPRequest(method: .GET, url: "/", headers: ["Accept": "text/html, application/json, application/xml;q=0.9, */*;q=0.8"])
        XCTAssertTrue(httpReq.accept.mediaTypes.contains(.html))
        XCTAssertEqual(httpReq.accept.comparePreference(for: .html, to: .xml), .orderedAscending)
        XCTAssertEqual(httpReq.accept.comparePreference(for: .plainText, to: .html), .orderedDescending)
        XCTAssertEqual(httpReq.accept.comparePreference(for: .html, to: .json), .orderedSame)
    }

    func testRemotePeer() throws {
        let worker = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let client = try HTTPClient.connect(
            config: .init(hostname: "httpbin.org", on: worker)
        ).wait()
        let httpReq = HTTPRequest(method: .GET, url: "/")
        let httpRes = try client.send(httpReq).wait()
        XCTAssertEqual(httpRes.remotePeer(on: client.channel).port, 80)
        try worker.syncShutdownGracefully()
    }
    
    func testLargeResponseClose() throws {
        struct LargeResponder: HTTPServerDelegate {
            func respond(to request: HTTPRequest, on channel: Channel) -> EventLoopFuture<HTTPResponse> {
                let res = HTTPResponse(
                    status: .ok,
                    body: String(repeating: "0", count: 2_000_000)
                )
                return channel.eventLoop.makeSucceededFuture(result: res)
            }
        }
        let worker = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let server = try HTTPServer.start(config: .init(
            hostname: "localhost",
            port: 8080,
            delegate: LargeResponder(),
            on: worker,
            errorHandler: { error in
                XCTFail("\(error)")
            }
        )) .wait()
    
        let client = try HTTPClient.connect(
            config: .init(hostname: "localhost", port: 8080, on: worker)
        ).wait()
        var req = HTTPRequest(method: .GET, url: "/")
        req.headers.replaceOrAdd(name: .connection, value: "close")
        let res = try client.send(req).wait()
        XCTAssertEqual(res.body.count, 2_000_000)
        try server.close().wait()
        try server.onClose.wait()
        try worker.syncShutdownGracefully()
    }
    
    func testUncleanShutdown() throws {
        // https://www.google.com/search?q=vapor
        let worker = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let client = try HTTPClient.connect(config: .init(
            hostname: "www.google.com",
            tlsConfig: .forClient(certificateVerification: .none),
            on: worker,
            errorHandler: { error in
                XCTFail("\(error)")
            }
        )).wait()
        let res = try client.send(.init(method: .GET, url: "/search?q=vapor")).wait()
        XCTAssertEqual(res.status, .ok)
        try! client.close().wait()
        try! client.onClose.wait()
        try worker.syncShutdownGracefully()
    }
}
