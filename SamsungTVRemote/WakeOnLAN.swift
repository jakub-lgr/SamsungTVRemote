import Darwin
import Foundation

/// Probuzení televize magic packetem (6× 0xFF a 16× MAC adresa) po UDP.
///
/// Broadcast iOS bez multicast oprávnění od Applu blokuje, proto paket posíláme hlavně
/// přímo na IP televize. Broadcast na podsíť jen zkusíme a jeho chybu ignorujeme.
nonisolated enum WakeOnLAN {
    enum Failure: LocalizedError {
        case invalidMAC
        case invalidIP
        case socket(Int32)

        var errorDescription: String? {
            switch self {
            case .invalidMAC: "MAC adresa televize není platná."
            case .invalidIP: "IP adresa televize není platná."
            case .socket(let code): "Paket pro zapnutí se nepodařilo odeslat (\(String(cString: strerror(code)))). Povolil jsi aplikaci přístup k místní síti?"
            }
        }
    }

    static func wake(mac: String, ip: String) throws {
        guard let packet = magicPacket(mac: mac) else { throw Failure.invalidMAC }
        guard TVConfig.isValidIPv4(ip) else { throw Failure.invalidIP }

        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { throw Failure.socket(errno) }
        defer { close(fd) }
        var enabled: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &enabled, socklen_t(MemoryLayout<Int32>.size))

        try send(packet, fd: fd, to: ip, port: 9)
        try? send(packet, fd: fd, to: ip, port: 7)
        // Předpokládá běžnou domácí síť /24.
        let subnetBroadcast = ip.split(separator: ".").dropLast().joined(separator: ".") + ".255"
        try? send(packet, fd: fd, to: subnetBroadcast, port: 9)
    }

    static func magicPacket(mac: String) -> Data? {
        let hex = Array(mac.filter(\.isHexDigit))
        guard hex.count == 12 else { return nil }
        let bytes = stride(from: 0, to: 12, by: 2).compactMap { UInt8(String(hex[$0...$0 + 1]), radix: 16) }
        guard bytes.count == 6 else { return nil }
        return Data(repeating: 0xFF, count: 6) + Data((0..<16).flatMap { _ in bytes })
    }

    private static func send(_ packet: Data, fd: Int32, to ip: String, port: UInt16) throws {
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        guard inet_pton(AF_INET, ip, &address.sin_addr) == 1 else { throw Failure.invalidIP }

        let sent = packet.withUnsafeBytes { buffer in
            withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(fd, buffer.baseAddress, buffer.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        guard sent == packet.count else { throw Failure.socket(errno) }
    }
}
