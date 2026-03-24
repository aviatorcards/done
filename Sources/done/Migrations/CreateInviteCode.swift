import Fluent

struct CreateInviteCode: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema("invite_codes")
            .id()
            .field("code", .string, .required)
            .field("email", .string, .required)
            .field("board_id", .uuid, .references("boards", "id", onDelete: .cascade))
            .field("inviter_id", .uuid, .required, .references("users", "id", onDelete: .cascade))
            .field("is_used", .bool, .required)
            .field("created_at", .datetime)
            .unique(on: "code")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema("invite_codes").delete()
    }
}
