import CoreWLAN
import Darwin
import Foundation

public enum WiFi {
    /// BSD name of the Wi-Fi interface (usually en0, but not always), or nil if the Mac has none.
    public static func interfaceName() -> String? {
        CWWiFiClient.shared().interface()?.interfaceName
    }

    public static func isPoweredOn() -> Bool {
        CWWiFiClient.shared().interface()?.powerOn() ?? false
    }
}

public struct InterfaceCounters: Equatable, Sendable {
    public var bytesIn: UInt64
    public var bytesOut: UInt64
}

public enum InterfaceStats {
    /// Reads 64-bit byte counters through sysctl NET_RT_IFLIST2.
    /// (`getifaddrs`' `if_data` counters are 32-bit and wrap every 4 GB.)
    public static func counters(for interface: String) -> InterfaceCounters? {
        let index = if_nametoindex(interface)
        guard index != 0 else { return nil }

        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &length, nil, 0) == 0, length > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, UInt32(mib.count), &buffer, &length, nil, 0) == 0 else { return nil }

        return buffer.withUnsafeBytes { raw -> InterfaceCounters? in
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= length {
                let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                guard header.ifm_msglen > 0 else { return nil }
                if Int32(header.ifm_type) == RTM_IFINFO2, UInt32(header.ifm_index) == index {
                    let msg = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    return InterfaceCounters(bytesIn: msg.ifm_data.ifi_ibytes, bytesOut: msg.ifm_data.ifi_obytes)
                }
                offset += Int(header.ifm_msglen)
            }
            return nil
        }
    }
}

/// Where internet-bound traffic actually leaves the Mac. Snail's rules sit on the Wi-Fi interface,
/// so traffic routed through a VPN tunnel (or another interface) never reaches them.
public enum RoutePath {
    public enum Bypass: Equatable, Sendable {
        /// A tunnel such as utun6 (WireGuard, IPsec, ...). Snail only sees one encrypted flow.
        case vpn(interface: String)
        /// A different physical interface, e.g. Ethernet.
        case otherInterface(String)

        public var explanation: String {
            switch self {
            case .vpn(let iface):
                return "A VPN (\(iface)) is carrying your traffic, so the Wi‑Fi limit can't see individual streams."
            case .otherInterface(let iface):
                return "Internet traffic is going over \(iface), not Wi‑Fi, so the limit doesn't apply."
            }
        }
    }

    /// Returns nil when internet traffic goes out over Wi-Fi as expected.
    public static func bypass(wifi: String) -> Bypass? {
        classify(outbound: outboundInterfaces(), wifi: wifi)
    }

    public static func classify(outbound: [String], wifi: String) -> Bypass? {
        guard let other = outbound.first(where: { $0 != wifi }) else { return nil }
        let tunnelPrefixes = ["utun", "ipsec", "ppp", "tun", "tap", "wg"]
        if tunnelPrefixes.contains(where: other.hasPrefix) { return .vpn(interface: other) }
        return .otherInterface(other)
    }

    /// Asks the kernel which interface it would use for public IPv4 and IPv6 destinations.
    /// A UDP `connect` only does a route lookup; no packets are sent.
    public static func outboundInterfaces() -> [String] {
        let targets: [(Int32, String)] = [(AF_INET, "8.8.8.8"), (AF_INET6, "2001:4860:4860::8888")]
        let locals = targets.compactMap { localAddress(family: $0.0, toward: $0.1) }
        guard !locals.isEmpty else { return [] }
        return locals.compactMap(interfaceName(for:))
    }

    private static func localAddress(family: Int32, toward host: String) -> String? {
        let fd = socket(family, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var storage = sockaddr_storage()
        var length: socklen_t
        if family == AF_INET {
            var addr = sockaddr_in()
            addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = in_port_t(53).bigEndian
            guard inet_pton(AF_INET, host, &addr.sin_addr) == 1 else { return nil }
            length = socklen_t(addr.sin_len)
            withUnsafeBytes(of: addr) { src in withUnsafeMutableBytes(of: &storage) { $0.copyMemory(from: src) } }
        } else {
            var addr = sockaddr_in6()
            addr.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
            addr.sin6_family = sa_family_t(AF_INET6)
            addr.sin6_port = in_port_t(53).bigEndian
            guard inet_pton(AF_INET6, host, &addr.sin6_addr) == 1 else { return nil }
            length = socklen_t(addr.sin6_len)
            withUnsafeBytes(of: addr) { src in withUnsafeMutableBytes(of: &storage) { $0.copyMemory(from: src) } }
        }
        let connected = withUnsafePointer(to: &storage) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, length) }
        }
        guard connected == 0 else { return nil }   // e.g. no IPv6 route
        var local = sockaddr_storage()
        var localLength = socklen_t(MemoryLayout<sockaddr_storage>.size)
        let ok = withUnsafeMutablePointer(to: &local) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &localLength) }
        }
        guard ok == 0 else { return nil }
        return numericHost(&local)
    }

    private static func interfaceName(for address: String) -> String? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            guard let sa = entry.pointee.ifa_addr else { continue }
            let family = Int32(sa.pointee.sa_family)
            guard family == AF_INET || family == AF_INET6 else { continue }
            var storage = sockaddr_storage()
            withUnsafeMutableBytes(of: &storage) { $0.copyMemory(from: UnsafeRawBufferPointer(start: sa, count: Int(sa.pointee.sa_len))) }
            if numericHost(&storage) == address { return String(cString: entry.pointee.ifa_name) }
        }
        return nil
    }

    private static func numericHost(_ storage: inout sockaddr_storage) -> String? {
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let length = socklen_t(storage.ss_len)
        let rc = withUnsafePointer(to: &storage) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getnameinfo($0, length, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            }
        }
        return rc == 0 ? String(cString: host) : nil
    }
}
