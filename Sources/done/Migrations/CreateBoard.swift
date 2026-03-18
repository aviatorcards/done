import Fluent

struct CreateBoard: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema("boards")
            .id()
            .field("title", .string, .required)
            .field("owner_id", .uuid, .required, .references("users", "id"))
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema("boards").delete()
    }
}
