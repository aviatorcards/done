import Fluent
import Vapor

func routes(_ app: Application) throws {
    app.get("login") { req async throws -> View in
        try await req.view.render("login", ["title": "Login"])
    }
    app.get("register") { req async throws -> View in
        try await req.view.render("register", ["title": "Register"])
    }
    
    app.get { req async throws -> Response in
        if let _ = req.cookies["token"] {
            return req.redirect(to: "/boards")
        }
        return try await req.view.render("landing", ["title": "Organize Your Life"]).encodeResponse(for: req)
    }

    app.get("hello") { req async -> String in
        "Hello, world!"
    }

    try app.register(collection: AuthController())
    try app.register(collection: BoardController())
    try app.register(collection: ColumnController())
    try app.register(collection: CardController())
    try app.register(collection: UserController())

    app.webSocket("board", ":boardID", "live") { req, ws in
        guard let boardID = req.parameters.get("boardID", as: UUID.self) else {
            ws.close(promise: nil)
            return
        }
        req.application.webSocketManager.connect(boardID: boardID, ws: ws)
    }
}
