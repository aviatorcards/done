import Vapor
import Fluent

struct AuthController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let auth = routes.grouped("auth")
        auth.post("register", use: register)
        auth.post("login", use: login)
        auth.get("logout", use: logout)
        
        routes.get("reset-password", use: renderResetPassword)
        routes.post("reset-password", use: handleResetPassword)
    }

    func logout(req: Request) async throws -> Response {
        let response = req.redirect(to: "/")
        response.cookies["token"] = .init(string: "", expires: Date(timeIntervalSince1970: 0), path: "/", isSecure: false, isHTTPOnly: true)
        return response
    }

    func register(req: Request) async throws -> Response {
        try UserDTO.validate(content: req)
        let dto = try req.content.decode(UserDTO.self)
        
        guard let password = dto.password, !password.isEmpty else {
            throw Abort(.badRequest, reason: "Password is required")
        }
        
        // Require invite code during alpha stage
        guard let code = dto.inviteCode, !code.isEmpty else {
            throw Abort(.badRequest, reason: "An invite code is required to join during the alpha stage.")
        }
        
        guard let inviteRecord = try await InviteCode.query(on: req.db)
            .filter(\.$code == code)
            .filter(\.$isUsed == false)
            .first() else {
            throw Abort(.badRequest, reason: "Invalid or already used invite code.")
        }
        
        let passwordHash = try Bcrypt.hash(password)
        let user = User(username: dto.username ?? "", email: dto.email ?? "", passwordHash: passwordHash)
        try await user.save(on: req.db)
        
        // Mark the invite as used and handle board membership
        inviteRecord.isUsed = true
        try await inviteRecord.save(on: req.db)
        
        if let boardID = inviteRecord.$board.id {
            let member = BoardMember(boardID: boardID, userID: try user.requireID(), role: "editor")
            try await member.save(on: req.db)
        }
        
        let payload = UserPayload(
            subject: .init(value: user.email),
            expiration: .init(value: Date().addingTimeInterval(24 * 60 * 60)),
            userID: try user.requireID()
        )
        
        let token = try req.jwt.sign(payload)
        
        let response = Response(status: .ok)
        try response.content.encode(["token": token])
        response.cookies["token"] = .init(string: token, expires: Date().addingTimeInterval(24 * 60 * 60), path: "/", isSecure: false, isHTTPOnly: true)
        
        return response
    }

    func login(req: Request) async throws -> Response {
        let dto = try req.content.decode(UserDTO.self)
        
        guard let user = try await User.query(on: req.db)
            .filter(\.$email == dto.email ?? "")
            .first() else {
            req.logger.warning("Login failed: User not found for email \(dto.email ?? "nil")")
            throw Abort(.unauthorized)
        }
        
        guard try Bcrypt.verify(dto.password ?? "", created: user.passwordHash) else {
            req.logger.warning("Login failed: Password mismatch for user \(user.email)")
            throw Abort(.unauthorized)
        }
        
        let payload = UserPayload(
            subject: .init(value: user.email),
            expiration: .init(value: Date().addingTimeInterval(24 * 60 * 60)),
            userID: try user.requireID()
        )
        
        let token = try req.jwt.sign(payload)
        
        let response = Response(status: .ok)
        try response.content.encode(["token": token])
        response.cookies["token"] = .init(string: token, expires: Date().addingTimeInterval(24 * 60 * 60), path: "/", isSecure: false, isHTTPOnly: true)
        
        return response
    }

    func renderResetPassword(req: Request) async throws -> View {
        guard let token = req.query[String.self, at: "token"] else {
            throw Abort(.badRequest, reason: "Missing reset token")
        }
        
        guard let user = try await User.query(on: req.db)
            .filter(\.$resetToken == token)
            .first() else {
            throw Abort(.notFound, reason: "Invalid reset token")
        }
        
        if let expires = user.resetTokenExpiresAt, expires < Date() {
            throw Abort(.badRequest, reason: "Reset token has expired")
        }
        
        return try await req.view.render("reset_password", ["token": token, "email": user.email])
    }

    func handleResetPassword(req: Request) async throws -> Response {
        let dto = try req.content.decode(UserDTO.self)
        guard let token = dto.inviteCode ?? req.query[String.self, at: "token"] else { // We reuse inviteCode from DTO for simplicity
            throw Abort(.badRequest, reason: "Missing token")
        }
        
        guard let newPassword = dto.password, !newPassword.isEmpty else {
            throw Abort(.badRequest, reason: "New password is required")
        }
        
        guard let user = try await User.query(on: req.db)
            .filter(\.$resetToken == token)
            .first() else {
            throw Abort(.notFound, reason: "Invalid or used token")
        }
        
        if let expires = user.resetTokenExpiresAt, expires < Date() {
            throw Abort(.badRequest, reason: "Token has expired")
        }
        
        user.passwordHash = try Bcrypt.hash(newPassword)
        user.resetToken = nil
        user.resetTokenExpiresAt = nil
        try await user.save(on: req.db)
        
        return req.redirect(to: "/login")
    }
}
