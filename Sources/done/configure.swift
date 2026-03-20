import NIOSSL
import Fluent
import FluentPostgresDriver
import FluentSQLiteDriver
import Leaf
import Vapor

// configures your application
public func configure(_ app: Application) async throws {
    // serve files from /Public folder
    app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))

    // Set max body size for file uploads (10MB)
    app.routes.defaultMaxBodySize = "10mb"

    // Use SQLite by default for development convenience
    app.databases.use(.sqlite(.file("done.sqlite")), as: .sqlite)
    
    // Optional: Switch back to Postgres if environment variables are present
    if let _ = Environment.get("DATABASE_HOST") {
        app.databases.use(DatabaseConfigurationFactory.postgres(configuration: .init(
            hostname: Environment.get("DATABASE_HOST") ?? "localhost",
            port: Environment.get("DATABASE_PORT").flatMap(Int.init(_:)) ?? SQLPostgresConfiguration.ianaPortNumber,
            username: Environment.get("DATABASE_USERNAME") ?? "vapor_username",
            password: Environment.get("DATABASE_PASSWORD") ?? "vapor_password",
            database: Environment.get("DATABASE_NAME") ?? "vapor_database",
            tls: .prefer(try .init(configuration: .clientDefault)))
        ), as: .psql)
    }

    app.migrations.add(CreateUser())
    app.migrations.add(AddAvatarToUser())
    app.migrations.add(CreateBoard())
    app.migrations.add(CreateColumn())
    app.migrations.add(CreateCard())
    app.migrations.add(AddIsCompletedToCard())
    app.migrations.add(CreateLabel())
    app.migrations.add(CreateCardLabel())
    app.migrations.add(CreateComment())

    // Configure JWT
    app.jwt.signers.use(.hs256(key: Environment.get("JWT_SECRET") ?? "secret"))

    app.views.use(.leaf)

    // register routes
    try routes(app)
}
