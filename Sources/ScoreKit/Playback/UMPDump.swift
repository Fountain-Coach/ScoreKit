import Foundation

public enum UMPDump {
    public static func hexWords(_ words: [UInt32]) -> String {
        words.map { String(format: "%08X", $0) }.joined(separator: " ")
    }
}

