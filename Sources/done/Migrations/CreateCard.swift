import Fluent

struct CreateCard: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema("cards")
            .id()
            .field("title", .string, .required)
            .field("description", .string, .required)
            .field("position", .int, .required)
            .field("due_date", .datetime)
            .field("priority", .string, .required)
            .field("column_id", .uuid, .required, .references("columns", "id"))
            .field("assignee_id", .uuid, .references("users", "id"))
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema("cards").delete()
    }
}
