import Fluent
import Vapor

final class User: Model, Content, Authenticatable, @unchecked Sendable {
    static let schema = "users"
    
    @ID(key: .id)
    var id: UUID?
    
    @Field(key: "username")
    var username: String
    
    @Field(key: "email")
    var email: String
    
    @Field(key: "password_hash")
    var passwordHash: String
    
    @Field(key: "reset_token")
    var resetToken: String?
    
    @Field(key: "reset_token_expires_at")
    var resetTokenExpiresAt: Date?
    
    @Field(key: "invite_credits")
    var inviteCredits: Int
    
    @Field(key: "last_invite_regen_at")
    var lastInviteRegenAt: Date?

    @Field(key: "avatar_url")
    var avatarUrl: String?
    
    @Field(key: "is_admin")
    var isAdmin: Bool
    
    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?
    
    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?
    
    @Siblings(through: BoardMember.self, from: \.$user, to: \.$board)
    var sharedBoards: [Board]
    
    @Children(for: \.$owner)
    var boards: [Board]
    
    init() { }
    
    init(id: UUID? = nil, username: String, email: String, passwordHash: String, avatarUrl: String? = nil, isAdmin: Bool = false, displayName: String? = nil, resetToken: String? = nil, resetTokenExpiresAt: Date? = nil, inviteCredits: Int = 3, lastInviteRegenAt: Date? = nil) {
        self.id = id
        self.username = username
        self.email = email
        self.passwordHash = passwordHash
        self.avatarUrl = avatarUrl
        self.isAdmin = isAdmin
        self.displayName = displayName
        self.resetToken = resetToken
        self.resetTokenExpiresAt = resetTokenExpiresAt
        self.inviteCredits = inviteCredits
        self.lastInviteRegenAt = lastInviteRegenAt ?? Date()
    }

    @Field(key: "display_name")
    var displayName: String?

    var initials: String {
        let name = (displayName ?? username).trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            let first = parts[0].prefix(1).uppercased()
            let second = parts[1].prefix(1).uppercased()
            return first + second
        } else {
            return String(name.prefix(2)).uppercased()
        }
    }

    var isEarlyAdopter: Bool {
        guard let createdAt = createdAt else { return false }
        // Cutoff: September 24, 2026
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 24
        guard let cutoff = Calendar.current.date(from: components) else { return false }
        return createdAt < cutoff
    }

    enum CodingKeys: String, CodingKey {
        case id, username, email, displayName, avatarUrl, isAdmin, createdAt, updatedAt
        case initials, isEarlyAdopter
        case resetToken, resetTokenExpiresAt
        case inviteCredits, lastInviteRegenAt
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(username, forKey: .username)
        try container.encode(email, forKey: .email)
        try container.encodeIfPresent(displayName, forKey: .displayName)
        try container.encodeIfPresent(avatarUrl, forKey: .avatarUrl)
        try container.encode(isAdmin, forKey: .isAdmin)
        try container.encode(initials, forKey: .initials)
        try container.encode(isEarlyAdopter, forKey: .isEarlyAdopter)
        try container.encodeIfPresent(resetToken, forKey: .resetToken)
        try container.encodeIfPresent(resetTokenExpiresAt, forKey: .resetTokenExpiresAt)
        try container.encode(inviteCredits, forKey: .inviteCredits)
        try container.encodeIfPresent(lastInviteRegenAt, forKey: .lastInviteRegenAt)
        if let createdAt = createdAt { try container.encode(createdAt, forKey: .createdAt) }
        if let updatedAt = updatedAt { try container.encode(updatedAt, forKey: .updatedAt) }
    }
}

extension User {
    func toDTO() -> UserDTO {
        .init(
            id: self.id,
            username: self.username,
            email: self.email,
            password: nil
        )
    }
    
    func regenerateInviteCredits() {
        let now = Date()
        guard let lastRegen = lastInviteRegenAt else {
            lastInviteRegenAt = now
            return
        }
        
        let secondsPerCredit: TimeInterval = 7 * 24 * 60 * 60 // 1 week
        let elapsed = now.timeIntervalSince(lastRegen)
        let creditsToAdd = Int(elapsed / secondsPerCredit)
        
        if creditsToAdd > 0 {
            let maxCredits = 5
            inviteCredits = min(maxCredits, inviteCredits + creditsToAdd)
            lastInviteRegenAt = lastRegen.addingTimeInterval(Double(creditsToAdd) * secondsPerCredit)
        }
    }

    func toPublic() -> UserDTO.Public {
        .init(id: self.id, username: self.username, email: self.email, displayName: self.displayName, avatarUrl: self.avatarUrl, inviteCredits: self.inviteCredits, isEarlyAdopter: self.isEarlyAdopter)
    }
}

extension User: ModelAuthenticatable {
    static var usernameKey: KeyPath<User, FieldProperty<User, String>> { \User.$email }
    static var passwordHashKey: KeyPath<User, FieldProperty<User, String>> { \User.$passwordHash }

    func verify(password: String) throws -> Bool {
        try Bcrypt.verify(password, created: self.passwordHash)
    }
}
