import Fluent

struct CreateBoardMember: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema("board_members")
            .id()
            .field("board_id", .uuid, .required, .references("boards", "id", onDelete: .cascade))
            .field("user_id", .uuid, .required, .references("users", "id", onDelete: .cascade))
            .field("role", .string, .required)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .unique(on: "board_id", "user_id")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema("board_members").delete()
    }
}
