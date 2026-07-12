//
//  WakeAndRemote.swift
//  AirPad
//
//  Remembering the Macs we've paired with (name + hardware MAC address from
//  server_info) and waking them over the network. A Wake-on-LAN magic packet
//  is 6x 0xFF followed by the target's MAC address 16 times, sent as a UDP
//  broadcast — the Mac's network hardware listens for it even while the
//  system sleeps, as long as "Wake for network access" is enabled in
//  System Settings → Battery/Energy.
//

import Foundation
import Darwin

/// A Mac this phone has talked to, persisted across launches.
struct KnownMac: Codable, Identifiable, Equatable {
    let id: String          // stable machineID from server_info
    var name: String
    var macAddress: String?
}

enum KnownMacStore {
    private static let key = "knownMacs.v1"

    static func all() -> [KnownMac] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let macs = try? JSONDecoder().decode([KnownMac].self, from: data) else { return [] }
        return macs
    }

    static func upsert(id: String, name: String, macAddress: String?) {
        var macs = all()
        if let i = macs.firstIndex(where: { $0.id == id }) {
            macs[i].name = name
            if let macAddress { macs[i].macAddress = macAddress }
        } else {
            macs.append(KnownMac(id: id, name: name, macAddress: macAddress))
        }
        if let data = try? JSONEncoder().encode(macs) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

enum WakeOnLAN {
    /// Broadcasts a magic packet for the given MAC address ("aa:bb:cc:dd:ee:ff").
    @discardableResult
    static func wake(macAddress: String) -> Bool {
        let bytes = macAddress
            .split(whereSeparator: { $0 == ":" || $0 == "-" })
            .compactMap { UInt8($0, radix: 16) }
        guard bytes.count == 6 else { return false }

        var packet = [UInt8](repeating: 0xFF, count: 6)
        for _ in 0..<16 { packet.append(contentsOf: bytes) }

        let sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard sock >= 0 else { return false }
        defer { close(sock) }
        var enable: Int32 = 1
        setsockopt(sock, SOL_SOCKET, SO_BROADCAST, &enable, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(9).bigEndian   // discard port, the WoL convention
        addr.sin_addr.s_addr = INADDR_BROADCAST

        let sent = packet.withUnsafeBufferPointer { buf in
            withUnsafePointer(to: &addr) { aptr in
                aptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    sendto(sock, buf.baseAddress, buf.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        return sent == packet.count
    }
}
