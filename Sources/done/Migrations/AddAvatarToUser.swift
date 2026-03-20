import Fluent

struct AddAvatarToUser: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema("users")
            .field("avatar_url", .string)
            .update()
    }

    func revert(on database: any Database) async throws {
        try await database.schema("users")
            .deleteField("avatar_url")
            .update()
    }
}
