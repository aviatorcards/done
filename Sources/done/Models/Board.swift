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
    
    @Siblings(through: BoardMember.self, from: \.$board, to: \.$user)
    var members: [User]
    
    init() { }
    
    init(id: UUID? = nil, title: String, ownerID: User.IDValue) {
        self.id = id
        self.title = title
        self.$owner.id = ownerID
    }
    
    var formattedUpdatedAt: String {
        guard let date = updatedAt ?? createdAt else { return "Never" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, owner, members, createdAt = "created_at", updatedAt = "updated_at", formattedUpdatedAt
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(formattedUpdatedAt, forKey: .formattedUpdatedAt)
        
        // Encode associations only if loaded
        try container.encodeIfPresent(self.$owner.value, forKey: .owner)
        try container.encode(self.$members.value ?? [], forKey: .members)
        
        if let createdAt = createdAt { try container.encode(createdAt, forKey: .createdAt) }
        if let updatedAt = updatedAt { try container.encode(updatedAt, forKey: .updatedAt) }
    }
}
