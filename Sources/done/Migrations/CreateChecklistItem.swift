import Fluent

struct CreateChecklistItem: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema("checklist_items")
            .id()
            .field("content", .string, .required)
            .field("is_completed", .bool, .required, .custom("DEFAULT false"))
            .field("position", .int, .required)
            .field("checklist_id", .uuid, .required, .references("checklists", "id", onDelete: .cascade))
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema("checklist_items").delete()
    }
}
