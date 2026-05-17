import Fluent

struct AddInviteCreditsToUser: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema("users")
            .field("invite_credits", .int, .required, .custom("DEFAULT 3"))
            .update()
        try await database.schema("users")
            .field("last_invite_regen_at", .datetime)
            .update()
    }

    func revert(on database: any Database) async throws {
        try await database.schema("users")
            .deleteField("invite_credits")
            .update()
        try await database.schema("users")
            .deleteField("last_invite_regen_at")
            .update()
    }
}
