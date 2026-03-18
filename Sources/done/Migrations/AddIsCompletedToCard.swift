import Fluent

struct AddIsCompletedToCard: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("cards")
            .field("is_completed", .bool, .required, .custom("DEFAULT FALSE"))
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("cards")
            .deleteField("is_completed")
            .update()
    }
}
