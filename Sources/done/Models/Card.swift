import Fluent
import Vapor

final class Card: Model, Content, @unchecked Sendable {
    static let schema = "cards"
    
    @ID(key: .id)
    var id: UUID?
    
    @Field(key: "title")
    var title: String
    
    @Field(key: "description")
    var description: String
    
    @Field(key: "position")
    var position: Int
    
    @Field(key: "due_date")
    var dueDate: Date?
    
    @Field(key: "priority")
    var priority: String

    @Field(key: "is_completed")
    var isCompleted: Bool
    
    @Parent(key: "column_id")
    var column: Column
    
    @OptionalParent(key: "assignee_id")
    var assignee: User?
    
    @Siblings(through: CardLabel.self, from: \.$card, to: \.$label)
    var labels: [Label]
    
    @Children(for: \.$card)
    var comments: [Comment]
    
    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?
    
    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?
    
    init() { }
    
    init(id: UUID? = nil, title: String, description: String, position: Int, dueDate: Date? = nil, priority: String, isCompleted: Bool = false, columnID: Column.IDValue, assigneeID: User.IDValue? = nil) {
        self.id = id
        self.title = title
        self.description = description
        self.position = position
        self.dueDate = dueDate
        self.priority = priority
        self.isCompleted = isCompleted
        self.$column.id = columnID
        self.$assignee.id = assigneeID
    }
    
    var formattedDueDate: String? {
        guard let date = dueDate else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    
    var priorityDisplay: (String, String) {
        switch priority.lowercased() {
        case "high":
            return ("‼️ High", "text-red-600 bg-red-100 dark:bg-red-900/30")
        case "low":
            return ("😴 Low", "text-slate-500 bg-slate-100 dark:bg-zinc-800")
        default:
            return ("⚡️ Medium", "text-amber-600 bg-amber-100 dark:bg-amber-900/30")
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, title, description, position, dueDate = "due_date", priority, isCompleted = "is_completed", column, assignee, labels, comments, createdAt = "created_at", updatedAt = "updated_at"
        case formattedDueDate, priorityDisplay, safeLabels
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(description, forKey: .description)
        try container.encode(position, forKey: .position)
        try container.encodeIfPresent(dueDate, forKey: .dueDate)
        try container.encode(priority, forKey: .priority)
        try container.encode(isCompleted, forKey: .isCompleted)
        try container.encodeIfPresent(formattedDueDate, forKey: .formattedDueDate)
        
        let display = priorityDisplay
        try container.encode(["text": display.0, "class": display.1], forKey: .priorityDisplay)
        
        // Always encode labels as an array for Leaf
        try container.encode(self.$labels.value ?? [], forKey: .safeLabels)
        
        if let createdAt = createdAt { try container.encode(createdAt, forKey: .createdAt) }
        if let updatedAt = updatedAt { try container.encode(updatedAt, forKey: .updatedAt) }
    }
}
