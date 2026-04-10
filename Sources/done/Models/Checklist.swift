import Fluent
import Vapor

final class Checklist: Model, Content, @unchecked Sendable {
    static let schema = "checklists"
    
    @ID(key: .id)
    var id: UUID?
    
    @Field(key: "title")
    var title: String
    
    @Parent(key: "owner_id")
    var owner: User
    
    @Children(for: \.$checklist)
    var items: [ChecklistItem]
    
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
    
    private enum CodingKeys: String, CodingKey {
        case id, title, items, owner, createdAt = "created_at", updatedAt = "updated_at"
        case safeItems
    }
    
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(title, forKey: .title)
        
        // Only encode items if they are loaded
        let items = self.$items.value ?? []
        try container.encode(items, forKey: .items)
        try container.encode(items, forKey: .safeItems)
        
        // Only encode owner if it's loaded
        try container.encodeIfPresent(self.$owner.value, forKey: .owner)
        
        if let createdAt = createdAt { try container.encode(createdAt, forKey: .createdAt) }
        if let updatedAt = updatedAt { try container.encode(updatedAt, forKey: .updatedAt) }
    }
}
