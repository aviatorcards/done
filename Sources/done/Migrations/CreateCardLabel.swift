import Fluent

struct CreateCardLabel: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema("card_label")
            .id()
            .field("card_id", .uuid, .required, .references("cards", "id"))
            .field("label_id", .uuid, .required, .references("labels", "id"))
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema("card_label").delete()
    }
}
