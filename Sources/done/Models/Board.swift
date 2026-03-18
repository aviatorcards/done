import Fluent
import Vapor

final class Board: Model, Content, @unchecked Sendable {
    static let schema = "boards"
    
    @ID(key: .id)
    var id: UUID?
    
    @Field(key: "title")
    var title: String
    
    @Parent(key: "owner_id")
    var owner: User
    
    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?
    
    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?
    
    init() { }
    
    init(id: UUID? = nil, title: String, ownerID: User.IDValue) {
        self.id = id
        self.title = title
        self.$owner.id = ownerID
    }
    
    var formattedUpdatedAt: String {
        guard let date = updatedAt else { return "Never" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
