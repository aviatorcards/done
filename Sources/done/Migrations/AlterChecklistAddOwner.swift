import Fluent

struct AlterChecklistAddOwner: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema("checklists")
            .deleteField("card_id")
            .field("owner_id", .uuid, .required, .references("users", "id", onDelete: .cascade))
            .update()
    }

    func revert(on database: any Database) async throws {
        try await database.schema("checklists")
            .deleteField("owner_id")
            .field("card_id", .uuid, .required, .references("cards", "id", onDelete: .cascade))
            .update()
    }
}
