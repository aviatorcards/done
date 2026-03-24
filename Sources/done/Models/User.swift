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
    
    @Field(key: "display_name")
    var displayName: String?

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
    
    init(id: UUID? = nil, username: String, email: String, passwordHash: String, avatarUrl: String? = nil, isAdmin: Bool = false, displayName: String? = nil) {
        self.id = id
        self.username = username
        self.email = email
        self.passwordHash = passwordHash
        self.avatarUrl = avatarUrl
        self.isAdmin = isAdmin
        self.displayName = displayName
    }

    var initials: String {
        let parts = username.split(separator: " ")
        if parts.count >= 2 {
            let first = parts[0].prefix(1).uppercased()
            let second = parts[1].prefix(1).uppercased()
            return first + second
        } else {
            return String(username.prefix(2)).uppercased()
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, username, email, displayName, avatarUrl, isAdmin, createdAt, updatedAt
        case initials
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
    
    func toPublic() -> UserDTO.Public {
        .init(id: self.id, username: self.username, email: self.email, displayName: self.displayName, avatarUrl: self.avatarUrl)
    }
}

extension User: ModelAuthenticatable {
    static var usernameKey: KeyPath<User, FieldProperty<User, String>> { \User.$email }
    static var passwordHashKey: KeyPath<User, FieldProperty<User, String>> { \User.$passwordHash }

    func verify(password: String) throws -> Bool {
        try Bcrypt.verify(password, created: self.passwordHash)
    }
}
