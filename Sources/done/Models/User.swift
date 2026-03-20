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
    
    @Field(key: "avatar_url")
    var avatarUrl: String?
    
    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?
    
    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?
    
    init() { }
    
    init(id: UUID? = nil, username: String, email: String, passwordHash: String, avatarUrl: String? = nil) {
        self.id = id
        self.username = username
        self.email = email
        self.passwordHash = passwordHash
        self.avatarUrl = avatarUrl
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
        .init(id: self.id, username: self.username, email: self.email, avatarUrl: self.avatarUrl)
    }
}

extension User: ModelAuthenticatable {
    static var usernameKey: KeyPath<User, FieldProperty<User, String>> { \User.$email }
    static var passwordHashKey: KeyPath<User, FieldProperty<User, String>> { \User.$passwordHash }

    func verify(password: String) throws -> Bool {
        try Bcrypt.verify(password, created: self.passwordHash)
    }
}
