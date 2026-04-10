import Fluent
import Vapor

final class ChecklistItem: Model, Content, @unchecked Sendable {
    static let schema = "checklist_items"
    
    @ID(key: .id)
    var id: UUID?
    
    @Field(key: "content")
    var content: String
    
    @Field(key: "is_completed")
    var isCompleted: Bool
    
    @Field(key: "position")
    var position: Int
    
    @Parent(key: "checklist_id")
    var checklist: Checklist
    
    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?
    
    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?
    
    init() { }
    
    init(id: UUID? = nil, content: String, isCompleted: Bool = false, position: Int, checklistID: Checklist.IDValue) {
        self.id = id
        self.content = content
        self.isCompleted = isCompleted
        self.position = position
        self.$checklist.id = checklistID
    }
    
    private enum CodingKeys: String, CodingKey {
        case id, content, isCompleted = "is_completed", position, createdAt = "created_at", updatedAt = "updated_at"
    }
    
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(content, forKey: .content)
        try container.encode(isCompleted, forKey: .isCompleted)
        try container.encode(position, forKey: .position)
        if let createdAt = createdAt { try container.encode(createdAt, forKey: .createdAt) }
        if let updatedAt = updatedAt { try container.encode(updatedAt, forKey: .updatedAt) }
    }
}
