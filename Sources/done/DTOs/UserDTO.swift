import Vapor

struct UserDTO: Content {
    var id: UUID?
    var username: String?
    var email: String?
    var displayName: String?
    var password: String?
    var newPassword: String?
    var currentPassword: String?
    var inviteCode: String?
    var inviteCredits: Int?
    
    struct Public: Content {
        var id: UUID?
        var username: String
        var email: String
        var displayName: String?
        var avatarUrl: String?
        var inviteCredits: Int?
    }
    
    func toPublic() -> Public {
        .init(id: id, username: username ?? "", email: email ?? "", displayName: displayName, avatarUrl: nil, inviteCredits: inviteCredits)
    }
}

extension UserDTO: Validatable {
    static func validations(_ validations: inout Validations) {
        validations.add("email", as: String.self, is: .email, required: false)
        validations.add("username", as: String.self, is: .count(3...), required: false)
        validations.add("password", as: String.self, is: .count(8...), required: false)
    }
}
