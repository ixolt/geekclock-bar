import Foundation
import Testing
@testable import GeekClockCore

/// Records requests and replays scripted results in order.
final class FakeTransport: HTTPTransport, @unchecked Sendable {
    enum Reply { case ok(Int, String), fail(Error) }
    private let lock = NSLock()
    private var replies: [Reply]
    private(set) var requests: [URLRequest] = []

    init(_ replies: [Reply]) { self.replies = replies }

    func send(_ request: URLRequest) async throws -> (Data, Int) {
        let reply: Reply = lock.withLock {
            requests.append(request)
            return replies.isEmpty ? .ok(200, "OK") : replies.removeFirst()
        }
        switch reply {
        case .ok(let status, let body): return (Data(body.utf8), status)
        case .fail(let error): throw error
        }
    }
}

private let host = "192.168.1.50"

@Test func uploadBuildsMultipart() async throws {
    let transport = FakeTransport([.ok(200, "")])
    try await GeekMagicClient(host: host, transport: transport).upload(.jpeg(Data([1, 2, 3])))
    let req = try #require(transport.requests.first)
    #expect(transport.requests.count == 1)
    #expect(req.httpMethod == "POST")
    #expect(req.url?.absoluteString == "http://192.168.1.50/doUpload?dir=/image/")
    #expect(req.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)
    let body = String(decoding: req.httpBody ?? Data(), as: UTF8.self)
    #expect(body.contains(#"name="file"; filename="claude.jpg""#))
    #expect(body.contains("Content-Type: image/jpeg"))
}

@Test func uploadTreatsUnparseableReplyAsSuccessWhenFileListed() async throws {
    let transport = FakeTransport([
        .fail(URLError(.cannotParseResponse)),
        .ok(200, "<a href='/image//claude.jpg'>claude.jpg</a>"),
    ])
    try await GeekMagicClient(host: host, transport: transport).upload(.jpeg(Data([1])))
    #expect(transport.requests.last?.url?.absoluteString == "http://192.168.1.50/filelist?dir=/image/")
}

@Test func uploadFailsWhenNotListed() async {
    let transport = FakeTransport([.fail(URLError(.cannotParseResponse)), .ok(200, "hamster.gif")])
    await #expect {
        try await GeekMagicClient(host: host, transport: transport).upload(.jpeg(Data([1])))
    } throws: { error in
        if case ClockError.badReply = error { return true }
        return false
    }
}

@Test func uploadUnreachable() async {
    let transport = FakeTransport([.fail(URLError(.cannotConnectToHost))])
    await #expect {
        try await GeekMagicClient(host: host, transport: transport).upload(.jpeg(Data([1])))
    } throws: { error in
        if case ClockError.unreachable = error { return true }
        return false
    }
}

@Test func showAppImageCallsBothEndpoints() async throws {
    let transport = FakeTransport([.ok(200, "OK"), .ok(200, "OK")])
    try await GeekMagicClient(host: host, transport: transport).showImage(named: "claude.jpg")
    #expect(transport.requests.map { $0.url?.absoluteString } == [
        "http://192.168.1.50/set?img=%2Fimage%2F%2Fclaude.jpg",
        "http://192.168.1.50/set?theme=3",
    ])
    #expect(transport.requests.allSatisfy { $0.httpMethod == "GET" })

    let refusing = FakeTransport([.ok(200, "ERR")])
    await #expect {
        try await GeekMagicClient(host: host, transport: refusing).showImage(named: "claude.jpg")
    } throws: { error in
        if case ClockError.badReply = error { return true }
        return false
    }
}

@Test func invalidHostThrows() async {
    for bad in ["", "not a host", "http://x"] {
        let transport = FakeTransport([])
        await #expect(throws: ClockError.invalidAddress) {
            try await GeekMagicClient(host: bad, transport: transport).upload(.jpeg(Data([1])))
        }
        #expect(transport.requests.isEmpty)
    }
}

@Test func uploadGIFUsesItsOwnNameAndType() async throws {
    let transport = FakeTransport([.ok(200, "")])
    try await GeekMagicClient(host: host, transport: transport).upload(.gif(Data([1])))
    let body = String(decoding: transport.requests.first?.httpBody ?? Data(), as: UTF8.self)
    #expect(body.contains(#"name="file"; filename="claude.gif""#))
    #expect(body.contains("Content-Type: image/gif"))
}

@Test func uploadConfirmsTheGIFByItsName() async {
    let transport = FakeTransport([.fail(URLError(.cannotParseResponse)), .ok(200, "claude.jpg")])
    await #expect {
        try await GeekMagicClient(host: host, transport: transport).upload(.gif(Data([1])))
    } throws: { error in
        if case ClockError.badReply = error { return true }
        return false
    }
}

@Test func showImageSelectsTheGivenFile() async throws {
    let transport = FakeTransport([.ok(200, "OK"), .ok(200, "OK")])
    try await GeekMagicClient(host: host, transport: transport).showImage(named: "claude.gif")
    #expect(transport.requests.first?.url?.absoluteString == "http://192.168.1.50/set?img=%2Fimage%2F%2Fclaude.gif")
}

/// Right after an upload the clock sometimes answers with an empty body.
@Test func showImageRetriesAnEmptyReplyOnce() async throws {
    let transport = FakeTransport([.ok(200, ""), .ok(200, "OK"), .ok(200, "OK")])
    try await GeekMagicClient(host: host, transport: transport).showImage(named: "claude.gif")
    #expect(transport.requests.map { $0.url?.absoluteString } == [
        "http://192.168.1.50/set?img=%2Fimage%2F%2Fclaude.gif",
        "http://192.168.1.50/set?img=%2Fimage%2F%2Fclaude.gif",
        "http://192.168.1.50/set?theme=3",
    ])
}
