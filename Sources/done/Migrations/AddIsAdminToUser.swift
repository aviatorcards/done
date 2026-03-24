import Fluent

struct AddIsAdminToUser: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema("users")
            .field("is_admin", .bool, .required, .custom("DEFAULT FALSE"))
            .update()
    }

    func revert(on database: any Database) async throws {
        try await database.schema("users")
            .deleteField("is_admin")
            .update()
    }
}
