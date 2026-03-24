import Foundation
import Crypto
import Vapor

enum FileSecurity {
    static func encrypt(_ data: Data, secret: String) throws -> Data {
        let key = try deriveKey(from: secret)
        let sealedBox = try AES.GCM.seal(data, using: key)
        return sealedBox.combined!
    }
    
    static func decrypt(_ data: Data, secret: String) throws -> Data {
        let key = try deriveKey(from: secret)
        let sealedBox = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(sealedBox, using: key)
    }
    
    private static func deriveKey(from secret: String) throws -> SymmetricKey {
        // Derive a 32-byte (256-bit) key from the secret
        let data = secret.data(using: .utf8) ?? Data()
        let hashed = SHA256.hash(data: data)
        return SymmetricKey(data: hashed)
    }
}
