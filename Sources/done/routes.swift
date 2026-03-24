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

    app.get("about") { req async throws -> View in
        try await req.view.render("about", ["title": "About Us"])
    }

    app.get("contact") { req async throws -> View in
        try await req.view.render("contact", ["title": "Contact"])
    }

    app.post("contact") { req async throws -> Response in
        struct ContactData: Content {
            let name: String
            let email: String
            let message: String
        }
        
        let data = try req.content.decode(ContactData.self)
        try await req.application.emailService.sendContactForm(name: data.name, email: data.email, message: data.message)
        
        // Return a response that HTMX will use to replace the form
        return try await req.view.render("partials/contact-success").encodeResponse(for: req)
    }

    app.get("docs") { req async throws -> View in
        try await req.view.render("docs", ["title": "Documentation"])
    }

    app.get("privacy") { req async throws -> View in
        try await req.view.render("privacy", ["title": "Privacy & GDPR"])
    }

    app.get("hello") { req async -> String in
        "Hello, world!"
    }

    try app.register(collection: AuthController())
    try app.register(collection: BoardController())
    try app.register(collection: ColumnController())
    try app.register(collection: CardController())
    try app.register(collection: UserController())
    try app.register(collection: AdminController())

    app.grouped(AuthMiddleware()).webSocket("board", ":boardID", "live") { req, ws in
        Task {
            do {
                guard let boardID = req.parameters.get("boardID", as: UUID.self) else {
                    try await ws.close()
                    return
                }
                
                let payload = try req.auth.require(UserPayload.self)
                guard let board = try await Board.find(boardID, on: req.db) else {
                    try await ws.close(code: .unacceptableData)
                    return
                }
                
                let isOwner = board.$owner.id == payload.userID
                let isMember = try await board.$members.query(on: req.db).filter(\User.$id == payload.userID).first() != nil
                
                guard isOwner || isMember else {
                    try await ws.close(code: .policyViolation)
                    return
                }
                
                req.application.webSocketManager.connect(boardID: boardID, ws: ws)
            } catch {
                try? await ws.close(code: .policyViolation)
            }
        }
    }
}
