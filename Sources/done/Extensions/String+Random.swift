import Foundation

extension String {
    /// Generates a human-readable, secure invite code.
    /// Uses an alphabet that avoids confusing characters (like 0 vs O, 2 vs Z).
    static func generateInviteCode(length: Int = 8) -> String {
        let alphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ3456789") // No 0, O, I, L, 1, 2, Z
        return String((0..<length).compactMap { _ in alphabet.randomElement() })
    }
    
    static func secureRandomString(count: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: count)
        for i in 0..<count {
            bytes[i] = UInt8.random(in: 0...255)
        }
        return bytes.map { String(format: "%02hhx", $0) }.joined()
    }
}
