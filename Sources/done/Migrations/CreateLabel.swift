import Fluent

struct CreateLabel: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema("labels")
            .id()
            .field("name", .string, .required)
            .field("color_hex", .string, .required)
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema("labels").delete()
    }
}
