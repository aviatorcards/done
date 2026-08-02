import Fluent
import Vapor

struct AuthController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let auth = routes.grouped("auth")
        auth.post("register", use: register)
        auth.post("login", use: login)
        auth.get("logout", use: logout)

        routes.get("forgot-password", use: renderForgotPassword)
        routes.post("forgot-password", use: handleForgotPassword)
        routes.get("reset-password", use: renderResetPassword)
        routes.post("reset-password", use: handleResetPassword)
    }

    func logout(req: Request) async throws -> Response {
        let response = req.redirect(to: "/")
        response.cookies["token"] = .init(
            string: "", expires: Date(timeIntervalSince1970: 0), path: "/", isSecure: false,
            isHTTPOnly: true)
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
            throw Abort(
                .badRequest, reason: "An invite code is required to join during the alpha stage.")
        }

        guard
            let inviteRecord = try await InviteCode.query(on: req.db)
                .filter(\.$code == code)
                .filter(\.$isUsed == false)
                .first()
        else {
            throw Abort(.badRequest, reason: "Invalid or already used invite code.")
        }

        let passwordHash = try Bcrypt.hash(password)
        let email = (dto.email ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let username = (dto.username ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let user = User(
            username: username, email: email, passwordHash: passwordHash)
        try await user.save(on: req.db)

        // Mark the invite as used and handle board membership
        inviteRecord.isUsed = true
        try await inviteRecord.save(on: req.db)

        if let boardID = inviteRecord.$board.id {
            let member = BoardMember(boardID: boardID, userID: try user.requireID(), role: "editor")
            try await member.save(on: req.db)
        }

        let sessionDuration: TimeInterval = 30 * 24 * 60 * 60  // 30 days
        let payload = UserPayload(
            subject: .init(value: user.email),
            expiration: .init(value: Date().addingTimeInterval(sessionDuration)),
            userID: try user.requireID()
        )

        let token = try req.jwt.sign(payload)

        let response = Response(status: .ok)
        try response.content.encode(["token": token], as: .json)
        response.cookies["token"] = .init(
            string: token, expires: Date().addingTimeInterval(sessionDuration), path: "/",
            isSecure: req.headers.first(name: "X-Forwarded-Proto") == "https"
                || req.application.environment == .production, isHTTPOnly: true)

        return response
    }

    func login(req: Request) async throws -> Response {
        let dto = try req.content.decode(UserDTO.self)
        let identifier = (dto.email ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let emailIdentifier = identifier.lowercased()

        let user = try await User.query(on: req.db)
            .group(.or) { qb in
                qb.filter(\.$email == emailIdentifier)
                qb.filter(\.$username == identifier)
            }
            .first()

        guard let user = user else {
            req.logger.warning("Login failed: User not found for identifier \(identifier)")
            throw Abort(.unauthorized)
        }

        guard try Bcrypt.verify(dto.password ?? "", created: user.passwordHash) else {
            req.logger.warning("Login failed: Password mismatch for user \(user.email)")
            throw Abort(.unauthorized)
        }

        let sessionDuration: TimeInterval = 30 * 24 * 60 * 60  // 30 days
        let payload = UserPayload(
            subject: .init(value: user.email),
            expiration: .init(value: Date().addingTimeInterval(sessionDuration)),
            userID: try user.requireID()
        )

        let token = try req.jwt.sign(payload)

        let response = Response(status: .ok)
        try response.content.encode(["token": token], as: .json)
        response.cookies["token"] = .init(
            string: token, expires: Date().addingTimeInterval(sessionDuration), path: "/",
            isSecure: req.headers.first(name: "X-Forwarded-Proto") == "https"
                || req.application.environment == .production, isHTTPOnly: true)

        return response
    }

    func renderResetPassword(req: Request) async throws -> View {
        guard let token = req.query[String.self, at: "token"] else {
            throw Abort(.badRequest, reason: "Missing reset token")
        }

        guard
            let user = try await User.query(on: req.db)
                .filter(\.$resetToken == token)
                .first()
        else {
            throw Abort(.notFound, reason: "Invalid reset token")
        }

        if let expires = user.resetTokenExpiresAt, expires < Date() {
            throw Abort(.badRequest, reason: "Reset token has expired")
        }

        return try await req.view.render("reset_password", ["token": token, "email": user.email])
    }

    func renderForgotPassword(req: Request) async throws -> View {
        try await req.view.render("forgot_password", ["title": "Forgot Password"])
    }

    func handleForgotPassword(req: Request) async throws -> Response {
        struct ForgotPasswordRequest: Content {
            let email: String
        }
        
        let dto = try req.content.decode(ForgotPasswordRequest.self)
        let email = dto.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        if let user = try await User.query(on: req.db)
            .filter(\.$email == email)
            .first() {
            let token = [UInt8].random(count: 32).hex
            user.resetToken = token
            user.resetTokenExpiresAt = Date().addingTimeInterval(24 * 60 * 60) // 24 hours
            try await user.save(on: req.db)
            
            try await req.application.emailService.sendPasswordReset(to: user.email, token: token)
        } else {
            req.logger.info("Password reset requested for non-existent email: \(email)")
        }
        
        let response = Response(status: .ok)
        try response.content.encode(["status": "success", "reason": "If a user is registered with that email, a password reset link has been sent."], as: .json)
        return response
    }

    func handleResetPassword(req: Request) async throws -> Response {
        let dto = try req.content.decode(UserDTO.self)
        guard let token = dto.inviteCode ?? req.query[String.self, at: "token"] else {  // We reuse inviteCode from DTO for simplicity
            throw Abort(.badRequest, reason: "Missing token")
        }

        guard let newPassword = dto.password, !newPassword.isEmpty else {
            throw Abort(.badRequest, reason: "New password is required")
        }

        guard newPassword.count >= 8 else {
            throw Abort(.badRequest, reason: "Password must be at least 8 characters long")
        }

        guard
            let user = try await User.query(on: req.db)
                .filter(\.$resetToken == token)
                .first()
        else {
            throw Abort(.notFound, reason: "Invalid or used token")
        }

        if let expires = user.resetTokenExpiresAt, expires < Date() {
            throw Abort(.badRequest, reason: "Token has expired")
        }

        user.passwordHash = try Bcrypt.hash(newPassword)
        user.resetToken = nil
        user.resetTokenExpiresAt = nil
        try await user.save(on: req.db)

        if req.headers.contentType == .json {
            let response = Response(status: .ok)
            try response.content.encode(["status": "success", "reason": "Password updated successfully"], as: .json)
            return response
        }

        return req.redirect(to: "/login")
    }
}
