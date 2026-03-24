import Fluent

struct AddPasswordResetToUser: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema("users")
            .field("reset_token", .string)
            .field("reset_token_expires_at", .datetime)
            .update()
    }

    func revert(on database: any Database) async throws {
        try await database.schema("users")
            .deleteField("reset_token")
            .deleteField("reset_token_expires_at")
            .update()
    }
}
