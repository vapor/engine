import NetKit
import XCTest

class WebSocketTests: XCTestCase {
    func testClient() throws {
        // ws://echo.websocket.org
        let client = try HTTPClient.connect(config: .init(
            hostname: "echo.websocket.org",
            on: self.eventLoopGroup
        )).wait()
        
        let message = "Hello, world!"
        let promise = self.eventLoopGroup.next().makePromise(of: String.self)
        
        var req = HTTPRequest()
        req.webSocketUpgrade { ws in
            ws.onText { ws, text in
                promise.succeed(result: text)
                ws.close(code: .normalClosure)
            }
            ws.send(text: message)
        }
        do {
            let res = try client.send(req).wait()
            XCTAssertEqual(res.status, .switchingProtocols)
        } catch {
            promise.fail(error: error)
        }
        try XCTAssertEqual(promise.futureResult.wait(), message)
        try client.close().wait()
    }

    func testClientTLS() throws {
        // wss://echo.websocket.org
        let client = try HTTPClient.connect(config: .init(
            hostname: "echo.websocket.org",
            tlsConfig: .forClient(certificateVerification: .none),
            on: self.eventLoopGroup
        )).wait()

        let message = "Hello, world!"
        let promise = self.eventLoopGroup.next().makePromise(of: String.self)
        
        var req = HTTPRequest()
        req.webSocketUpgrade { ws in
            ws.onText { ws, text in
                promise.succeed(result: text)
                ws.close(code: .normalClosure)
            }
            ws.send(text: message)
        }
        do {
            let res = try client.send(req).wait()
            XCTAssertEqual(res.status, .switchingProtocols)
        } catch {
            promise.fail(error: error)
        }
        try XCTAssertEqual(promise.futureResult.wait(), message)
        try client.close().wait()
    }

    func testServer() throws {
        let delegate = WebSocketServerDelegate { ws, req in
            ws.send(text: req.url.path)
            ws.onText { ws, string in
                ws.send(text: string.reversed())
                if string == "close" {
                    ws.close()
                }
            }
            ws.onBinary { ws, data in
                print("data: \(data)")
            }
            ws.onCloseCode { code in
                print("code: \(code)")
            }
            ws.onClose.whenSuccess {
                print("closed")
            }
        }
        let server = try HTTPServer.start(config: .init(
            hostname: "127.0.0.1",
            port: 8888,
            delegate: delegate,
            on: self.eventLoopGroup
        )).wait()
        print(server)
        try server.close().wait()
        // uncomment to test websocket server
        // try server.onClose.wait()
    }


    func testServerContinuation() throws {
        let promise = self.eventLoopGroup.next().makePromise(of: String.self)
        let delegate = WebSocketServerDelegate { ws, req in
            ws.onText { ws, text in
                promise.succeed(result: text)
            }
        }
        let server = try HTTPServer.start(config: .init(
            hostname: "127.0.0.1",
            port: 8888,
            delegate: delegate,
            on: self.eventLoopGroup
        )).wait()
        print(server)

        
        // ws://echo.websocket.org
        let client = try HTTPClient.connect(config: .init(
            hostname: "127.0.0.1",
            port: 8888,
            on: self.eventLoopGroup
        )).wait()
        
        var req = HTTPRequest()
        req.webSocketUpgrade { ws in
            ws.send(raw: Array("Hello, ".utf8), opcode: .text, fin: false)
            ws.send(raw: Array("world".utf8), opcode: .continuation, fin: false)
            ws.send(raw: Array("!".utf8), opcode: .continuation)
        }
        do {
            let res = try client.send(req).wait()
            XCTAssertEqual(res.status, .switchingProtocols)
        } catch {
            promise.fail(error: error)
        }
        try XCTAssertEqual(promise.futureResult.wait(), "Hello, world!")
        try client.close().wait()
        try server.close().wait()
    }
    
    var eventLoopGroup: EventLoopGroup!
    
    override func setUp() {
        self.eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 8)
    }
    
    override func tearDown() {
        try! self.eventLoopGroup.syncShutdownGracefully()
    }
}

struct WebSocketServerDelegate: HTTPServerDelegate {
    let onUpgrade: (WebSocket, HTTPRequest) -> ()
    init(onUpgrade: @escaping (WebSocket, HTTPRequest) -> ()) {
        self.onUpgrade = onUpgrade
    }
    
    func respond(to req: HTTPRequest, on channel: Channel) -> EventLoopFuture<HTTPResponse> {
        guard req.isRequestingUpgrade(to: "websocket") else {
            return channel.eventLoop.makeFailedFuture(error: HTTPError(identifier: "upgrade"))
        }
        
        
        do {
            var res = HTTPResponse()
            try res.webSocketUpgrade(for: req) { ws in
                self.onUpgrade(ws, req)
            }
            return channel.eventLoop.makeSucceededFuture(result: res)
        } catch {
            return channel.eventLoop.makeFailedFuture(error: error)
        }
    }
    
    
}
