import Foundation

/// Exact volume and mute via the UPnP RenderingControl service (port 9197).
///
/// The WebSocket API only has VOL+/VOL− keys; the volume number can only be set and read this way.
/// The range is 0–100.
nonisolated struct TVVolume {
    enum Failure: LocalizedError {
        case unexpectedResponse

        var errorDescription: String? {
            "The TV didn't answer the volume request as expected."
        }
    }

    static let range = 0...100

    let host: String

    func current() async throws -> Int {
        let body = try await call("GetVolume", arguments: "<Channel>Master</Channel>")
        guard let value = Int(try Self.element("CurrentVolume", in: body)) else { throw Failure.unexpectedResponse }
        return value
    }

    func isMuted() async throws -> Bool {
        let body = try await call("GetMute", arguments: "<Channel>Master</Channel>")
        return try Self.element("CurrentMute", in: body) == "1"
    }

    func setMuted(_ muted: Bool) async throws {
        _ = try await call("SetMute", arguments: "<Channel>Master</Channel><DesiredMute>\(muted ? 1 : 0)</DesiredMute>")
    }

    func set(_ value: Int) async throws {
        let clamped = min(max(value, Self.range.lowerBound), Self.range.upperBound)
        _ = try await call("SetVolume", arguments: "<Channel>Master</Channel><DesiredVolume>\(clamped)</DesiredVolume>")
    }

    private static func element(_ name: String, in body: String) throws -> String {
        guard let start = body.range(of: "<\(name)>"),
              let end = body.range(of: "</\(name)>", range: start.upperBound..<body.endIndex) else {
            throw Failure.unexpectedResponse
        }
        return body[start.upperBound..<end.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func call(_ action: String, arguments: String) async throws -> String {
        guard let url = URL(string: "http://\(host):9197/upnp/control/RenderingControl1") else {
            throw URLError(.badURL)
        }
        let service = "urn:schemas-upnp-org:service:RenderingControl:1"
        var request = URLRequest(url: url, timeoutInterval: 4)
        request.httpMethod = "POST"
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.setValue("\"\(service)#\(action)\"", forHTTPHeaderField: "SOAPACTION")
        request.httpBody = Data("""
            <?xml version="1.0" encoding="utf-8"?>
            <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
            <s:Body><u:\(action) xmlns:u="\(service)"><InstanceID>0</InstanceID>\(arguments)</u:\(action)></s:Body>
            </s:Envelope>
            """.utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw Failure.unexpectedResponse }
        return String(decoding: data, as: UTF8.self)
    }
}
