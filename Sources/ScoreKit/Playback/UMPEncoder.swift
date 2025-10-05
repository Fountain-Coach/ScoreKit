import Foundation

public enum UMPEncodingMode: Sendable {
    case midi1_32bit // Message Type 0x2 (32-bit)
    case midi2_64bit // Message Type 0x4 (64-bit)
}

public enum UMPEncoder {
    public static func encode(_ msg: UMPMessage, group: UInt8 = 0, mode: UMPEncodingMode) -> [UInt32] {
        switch mode {
        case .midi1_32bit: return encodeMIDI1(msg, group: group)
        case .midi2_64bit: return encodeMIDI2(msg, group: group)
        }
    }

    private static func encodeMIDI1(_ msg: UMPMessage, group: UInt8) -> [UInt32] {
        // MIDI 1.0 Channel Voice in UMP32
        // Word: [MT:4|Group:4] [Status:8] [Data1:8] [Data2:8]
        let mt: UInt8 = 0x2
        var status: UInt8 = 0
        var d1: UInt8 = 0
        var d2: UInt8 = 0
        switch msg {
        case let .noteOn(channel, key, velocity):
            status = 0x90 | (channel & 0x0F)
            d1 = key
            d2 = UInt8((UInt32(velocity) * 127 + 32767) / 65535) // downscale 16-bit to 7-bit
        case let .noteOff(channel, key, velocity):
            status = 0x80 | (channel & 0x0F)
            d1 = key
            d2 = UInt8((UInt32(velocity) * 127 + 32767) / 65535)
        case let .controlChange(channel, controller, value):
            status = 0xB0 | (channel & 0x0F)
            d1 = controller
            d2 = UInt8((UInt32(value) * 127 + 32767) / 65535)
        }
        let w: UInt32 = (UInt32(mt << 4 | (group & 0x0F)) << 24)
            | (UInt32(status) << 16)
            | (UInt32(d1) << 8)
            | UInt32(d2)
        return [w]
    }

    private static func encodeMIDI2(_ msg: UMPMessage, group: UInt8) -> [UInt32] {
        // MIDI 2.0 Channel Voice in UMP64
        // Word1: [MT:4|Group:4] [Status:8] [Note/Controller:8] [AttrType:8]
        // Word2: [Value 16-bit] [AttrData 16-bit]
        let mt: UInt8 = 0x4
        var status: UInt8 = 0
        var data: UInt8 = 0
        var attrType: UInt8 = 0 // 0 = none
        var value16: UInt16 = 0
        switch msg {
        case let .noteOn(channel, key, velocity):
            status = 0x90 | (channel & 0x0F)
            data = key
            value16 = velocity
        case let .noteOff(channel, key, velocity):
            status = 0x80 | (channel & 0x0F)
            data = key
            value16 = velocity
        case let .controlChange(channel, controller, value):
            status = 0xB0 | (channel & 0x0F)
            data = controller
            value16 = value
        }
        let w1: UInt32 = (UInt32(mt << 4 | (group & 0x0F)) << 24)
            | (UInt32(status) << 16)
            | (UInt32(data) << 8)
            | UInt32(attrType)
        let w2: UInt32 = (UInt32(value16) << 16) | 0x0000
        return [w1, w2]
    }
}

