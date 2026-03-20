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

    app.routes.defaultMaxBodySize = "10mb"

    app.databases.use(.sqlite(.file("done.sqlite")), as: .sqlite)

    if Environment.get("DATABASE_HOST") != nil {
        app.databases.use(
            DatabaseConfigurationFactory.postgres(
                configuration: .init(
                    hostname: Environment.get("DATABASE_HOST") ?? "localhost",
                    port: Environment.get("DATABASE_PORT").flatMap(Int.init(_:))
                        ?? SQLPostgresConfiguration.ianaPortNumber,
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

    app.jwt.signers.use(.hs256(key: Environment.get("JWT_SECRET") ?? "secret"))

    app.views.use(.leaf)

    try routes(app)
}
