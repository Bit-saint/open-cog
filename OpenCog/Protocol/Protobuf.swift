import Foundation

/// Minimal protobuf wire-format helpers. Zwift messages only use varints (wire type 0)
/// and length-delimited nested messages (wire type 2). See docs/BLUETOOTH_PROTOCOL.md §2.
enum Protobuf {
    enum WireType: UInt64 {
        case varint = 0
        case fixed64 = 1
        case lengthDelimited = 2
        case fixed32 = 5
    }

    /// Unsigned LEB128 varint.
    static func varint(_ value: UInt64) -> [UInt8] {
        var value = value
        var out: [UInt8] = []
        repeat {
            var byte = UInt8(value & 0x7F)
            value >>= 7
            if value != 0 { byte |= 0x80 }
            out.append(byte)
        } while value != 0
        return out
    }

    /// Reads a varint starting at `index` and advances it. Returns nil if the buffer ends mid-varint.
    static func readVarint(_ bytes: [UInt8], _ index: inout Int) -> UInt64? {
        var value: UInt64 = 0
        var shift: UInt64 = 0
        while index < bytes.count {
            let byte = bytes[index]
            index += 1
            if shift < 64 {
                value |= UInt64(byte & 0x7F) << shift
            }
            if byte & 0x80 == 0 { return value }
            shift += 7
        }
        return nil
    }

    /// sint32/sint64 zigzag encoding: 0 → 0, -1 → 1, 1 → 2, -2 → 3 …
    static func zigzag(_ value: Int64) -> UInt64 {
        UInt64(bitPattern: (value << 1) ^ (value >> 63))
    }

    static func unzigzag(_ value: UInt64) -> Int64 {
        Int64(bitPattern: value >> 1) ^ -Int64(bitPattern: value & 1)
    }

    /// A varint field: key + value.
    static func field(_ number: UInt64, _ value: UInt64) -> [UInt8] {
        varint(number << 3 | WireType.varint.rawValue) + varint(value)
    }

    /// A length-delimited (nested message) field: key + length + body.
    static func message(_ number: UInt64, _ body: [UInt8]) -> [UInt8] {
        varint(number << 3 | WireType.lengthDelimited.rawValue) + varint(UInt64(body.count)) + body
    }

    /// Decodes the varint fields of a flat message. Nested messages are skipped.
    /// Proto3 omits zero values, so callers should treat a missing field as 0.
    static func varintFields(_ bytes: [UInt8], from start: Int = 0) -> [Int: UInt64] {
        var index = start
        var out: [Int: UInt64] = [:]
        while index < bytes.count {
            guard let key = readVarint(bytes, &index) else { break }
            let number = Int(key >> 3)
            switch WireType(rawValue: key & 0x7) {
            case .varint:
                guard let value = readVarint(bytes, &index) else { return out }
                out[number] = value
            case .lengthDelimited:
                guard let length = readVarint(bytes, &index) else { return out }
                index += Int(length)
            case .fixed64:
                index += 8
            case .fixed32:
                index += 4
            case nil:
                return out
            }
        }
        return out
    }
}
