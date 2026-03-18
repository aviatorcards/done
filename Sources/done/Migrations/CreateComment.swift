import Fluent

struct CreateComment: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema("comments")
            .id()
            .field("text", .string, .required)
            .field("card_id", .uuid, .required, .references("cards", "id"))
            .field("user_id", .uuid, .required, .references("users", "id"))
            .field("created_at", .datetime)
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema("comments").delete()
    }
}
