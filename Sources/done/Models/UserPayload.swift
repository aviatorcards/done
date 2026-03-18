import Vapor
@preconcurrency import JWT

final class UserPayload: JWTPayload, Content, @unchecked Sendable {
    enum CodingKeys: String, CodingKey {
        case subject = "sub"
        case expiration = "exp"
        case userID = "uid"
    }

    var subject: SubjectClaim
    var expiration: ExpirationClaim
    var userID: UUID

    init(subject: SubjectClaim, expiration: ExpirationClaim, userID: UUID) {
        self.subject = subject
        self.expiration = expiration
        self.userID = userID
    }

    func verify(using signer: JWTSigner) throws {
        try self.expiration.verifyNotExpired()
    }
}

extension UserPayload: Authenticatable { }
