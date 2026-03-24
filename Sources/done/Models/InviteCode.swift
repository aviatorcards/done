import Fluent
import Vapor

final class InviteCode: Model, Content, @unchecked Sendable {
    static let schema = "invite_codes"
    
    @ID(key: .id)
    var id: UUID?
    
    @Field(key: "code")
    var code: String
    
    @Field(key: "email")
    var email: String
    
    @OptionalParent(key: "board_id")
    var board: Board?
    
    @Parent(key: "inviter_id")
    var inviter: User
    
    @Field(key: "is_used")
    var isUsed: Bool
    
    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?
    
    init() { }
    
    init(id: UUID? = nil, code: String, email: String, boardID: Board.IDValue? = nil, inviterID: User.IDValue) {
        self.id = id
        self.code = code
        self.email = email
        self.$board.id = boardID
        self.$inviter.id = inviterID
        self.isUsed = false
    }
}
