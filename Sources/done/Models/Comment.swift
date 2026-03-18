import Fluent
import Vapor

final class Comment: Model, Content, @unchecked Sendable {
    static let schema = "comments"
    
    @ID(key: .id)
    var id: UUID?
    
    @Field(key: "text")
    var text: String
    
    @Parent(key: "card_id")
    var card: Card
    
    @Parent(key: "user_id")
    var user: User
    
    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?
    
    init() { }
    
    init(id: UUID? = nil, text: String, cardID: Card.IDValue, userID: User.IDValue) {
        self.id = id
        self.text = text
        self.$card.id = cardID
        self.$user.id = userID
    }
}
