import Foundation

public protocol HTTPTransport: Sendable {
    /// Returns the body and HTTP status code.
    func send(_ request: URLRequest) async throws -> (Data, Int)
}

public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 10
        session = URLSession(configuration: config)
    }

    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        let (data, response) = try await session.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}

public enum ClockError: Error, Equatable {
    case invalidAddress
    case badReply(String)
    case unreachable(String)
}

/// A picture for the clock and the file it is stored under.
public struct ClockImage: Equatable, Sendable {
    public var data: Data
    public var fileName: String
    public var contentType: String

    public static func jpeg(_ data: Data) -> ClockImage {
        ClockImage(data: data, fileName: "claude.jpg", contentType: "image/jpeg")
    }

    public static func gif(_ data: Data) -> ClockImage {
        ClockImage(data: data, fileName: "claude.gif", contentType: "image/gif")
    }
}

/// Talks to a GeekMagic SmallTV-Ultra over its local HTTP API.
public struct GeekMagicClient: Sendable {
    private let host: String
    private let transport: HTTPTransport

    public init(host: String, transport: HTTPTransport) {
        self.host = host.trimmingCharacters(in: .whitespaces)
        self.transport = transport
    }

    /// Overwrites /image/<fileName> on the clock.
    public func upload(_ image: ClockImage) async throws {
        let boundary = "geekclock-\(UUID().uuidString)"
        var request = URLRequest(url: try url("/doUpload?dir=/image/"))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"\(image.fileName)\"\r\n".utf8))
        body.append(Data("Content-Type: \(image.contentType)\r\n\r\n".utf8))
        body.append(image.data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        request.httpBody = body

        do {
            let (_, status) = try await transport.send(request)
            guard status == 200 else { throw ClockError.badReply("HTTP \(status)") }
        } catch let error as URLError where Self.isGarbledReply(error) {
            // The firmware answers with two conflicting Content-Length
            // headers, which URLSession rejects although the upload worked.
            // Confirm by listing the image folder.
            let (listing, _) = try await send(URLRequest(url: try url("/filelist?dir=/image/")))
            guard String(decoding: listing, as: UTF8.self).contains(image.fileName) else {
                throw ClockError.badReply("upload not confirmed")
            }
        } catch let error as URLError {
            throw ClockError.unreachable(error.localizedDescription)
        }
    }

    /// Puts the clock in Photo Album mode showing /image/<fileName>.
    public func showImage(named fileName: String) async throws {
        for path in ["/set?img=%2Fimage%2F%2F\(fileName)", "/set?theme=3"] {
            var reply = try await command(path)
            if reply.isEmpty {
                // Still busy with the upload that came just before; ask again.
                try await Task.sleep(for: .milliseconds(500))
                reply = try await command(path)
            }
            guard reply == "OK" else { throw ClockError.badReply(reply) }
        }
    }

    private func command(_ path: String) async throws -> String {
        let (body, _) = try await send(URLRequest(url: try url(path)))
        return String(decoding: body, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func send(_ request: URLRequest) async throws -> (Data, Int) {
        do {
            return try await transport.send(request)
        } catch let error as URLError {
            throw ClockError.unreachable(error.localizedDescription)
        }
    }

    private func url(_ path: String) throws -> URL {
        guard host.range(of: #"^[A-Za-z0-9.-]+$"#, options: .regularExpression) != nil,
              let url = URL(string: "http://\(host)\(path)") else { throw ClockError.invalidAddress }
        return url
    }

    private static func isGarbledReply(_ error: URLError) -> Bool {
        [.cannotParseResponse, .badServerResponse, .networkConnectionLost].contains(error.code)
    }
}
