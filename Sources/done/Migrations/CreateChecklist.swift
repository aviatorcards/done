import Fluent

struct CreateChecklist: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema("checklists")
            .id()
            .field("title", .string, .required)
            .field("owner_id", .uuid, .required, .references("users", "id", onDelete: .cascade))
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema("checklists").delete()
    }
}
