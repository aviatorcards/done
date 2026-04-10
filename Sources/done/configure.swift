import Fluent
import FluentPostgresDriver
import FluentSQLiteDriver
import Leaf
import NIOSSL
import Vapor

public func configure(_ app: Application) async throws {

    if app.environment == .development {
        app.http.server.configuration.hostname = "127.0.0.1"
    } else {
        app.http.server.configuration.hostname = "0.0.0.0"
    }

    if let port = Environment.get("PORT").flatMap(Int.init) {
        app.http.server.configuration.port = port
    }

    app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))
    EmailService.configure(app)

    app.routes.defaultMaxBodySize = "10mb"

    if let host = Environment.get("DATABASE_HOST") {
        app.databases.use(
            DatabaseConfigurationFactory.postgres(
                configuration: .init(
                    hostname: host,
                    port: Environment.get("DATABASE_PORT").flatMap(Int.init(_:))
                        ?? SQLPostgresConfiguration.ianaPortNumber,
                    username: Environment.get("DATABASE_USERNAME") ?? "vapor_username",
                    password: Environment.get("DATABASE_PASSWORD") ?? "vapor_password",
                    database: Environment.get("DATABASE_NAME") ?? "vapor_database",
                    tls: .prefer(try .init(configuration: .clientDefault)))
            ), as: .psql, isDefault: true)
    } else {
        app.logger.info("No DATABASE_HOST found. Defaulting to SQLite.")
        app.databases.use(.sqlite(.file("done.sqlite")), as: .sqlite, isDefault: true)
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
    app.migrations.add(CreateChecklist())
    app.migrations.add(CreateChecklistItem())
    app.migrations.add(AlterChecklistAddOwner())
    app.migrations.add(CreateBoardMember())
    app.migrations.add(CreateInviteCode())
    app.migrations.add(AddIsAdminToUser())
    app.migrations.add(AddDisplayNameToUser())
    app.migrations.add(AddPasswordResetToUser())
    app.migrations.add(AddInviteCreditsToUser())
    app.migrations.add(MigrateAvatarUrls())
    app.migrations.add(SeedAdmin())
    // app.migrations.add(UpdateAdminPassword())

    let jwtSecret: String
    if app.environment == .production {
        guard let secret = Environment.get("JWT_SECRET") else {
            app.logger.critical("JWT_SECRET must be set in production.")
            fatalError("Missing environment variable: JWT_SECRET")
        }
        jwtSecret = secret
    } else {
        jwtSecret = Environment.get("JWT_SECRET") ?? "development-secret-only"
        if jwtSecret == "development-secret-only" {
            app.logger.warning(
                "Using insecure default JWT_SECRET for development. Change this as soon as possible."
            )
        }
    }
    app.jwt.signers.use(.hs256(key: jwtSecret))

    app.views.use(.leaf)

    try routes(app)

    // Ensure migrations are run before attempting to set admins
    try await app.autoMigrate()

    // Support setting admin from environment
    if let adminEmail = Environment.get("ADMIN_EMAIL") {
        _ = try await User.query(on: app.db)
            .filter(\.$email == adminEmail)
            .set(\.$isAdmin, to: true)
            .update()
    }
}
