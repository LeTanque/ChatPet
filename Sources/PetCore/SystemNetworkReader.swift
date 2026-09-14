import Darwin
import Foundation

/// macOS routing sysctl exposes 64-bit interface byte counters; no packet capture or privileges.
public struct SystemNetworkReader: Sendable {
    public init() {}
    public func read() throws -> [String: InterfaceCounters] {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        // The interface list may grow between size and data calls. Retry that race.
        for _ in 0..<3 {
            var size = 0
            guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            guard size > 0, size < 16_777_216 else { return [:] }
            var buffer = [UInt8](repeating: 0, count: size)
            let result = buffer.withUnsafeMutableBytes {
                sysctl(&mib, UInt32(mib.count), $0.baseAddress, &size, nil, 0)
            }
            if result != 0 {
                if errno == ENOMEM { continue }
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            return buffer.withUnsafeBytes { bytes in
                var interfaces: [String: InterfaceCounters] = [:]
                var offset = 0
                while offset + 4 <= size {
                    let length = Int(bytes.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
                    guard length >= 4, offset + length <= size else { break }
                    defer { offset += length }
                    guard bytes[offset + 3] == UInt8(RTM_IFINFO2), length >= MemoryLayout<if_msghdr2>.size else { continue }
                    let header = bytes.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    guard header.ifm_flags & IFF_UP != 0, header.ifm_flags & IFF_LOOPBACK == 0 else { continue }
                    var nameBuffer = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
                    guard if_indextoname(UInt32(header.ifm_index), &nameBuffer) != nil else { continue }
                    let name = nameBuffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
                    interfaces[name] = InterfaceCounters(received: header.ifm_data.ifi_ibytes,
                                                          sent: header.ifm_data.ifi_obytes)
                }
                return interfaces
            }
        }
        throw POSIXError(.ENOMEM)
    }
}
