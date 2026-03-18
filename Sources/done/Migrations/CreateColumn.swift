import Fluent

struct CreateColumn: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema("columns")
            .id()
            .field("title", .string, .required)
            .field("position", .int, .required)
            .field("board_id", .uuid, .required, .references("boards", "id"))
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema("columns").delete()
    }
}
