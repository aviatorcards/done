import Vapor
import Fluent

struct AuthController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let auth = routes.grouped("auth")
        auth.post("register", use: register)
        auth.post("login", use: login)
        auth.get("logout", use: logout)
    }

    func logout(req: Request) async throws -> Response {
        let response = req.redirect(to: "/")
        response.cookies["token"] = .init(string: "", expires: Date(timeIntervalSince1970: 0), isSecure: false, isHTTPOnly: true)
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
        response.cookies["token"] = .init(string: token, expires: Date().addingTimeInterval(24 * 60 * 60), isSecure: false, isHTTPOnly: true)
        
        return response
    }

    func login(req: Request) async throws -> Response {
        let dto = try req.content.decode(UserDTO.self)
        
        guard let user = try await User.query(on: req.db)
            .filter(\.$email == dto.email ?? "")
            .first() else {
            throw Abort(.unauthorized)
        }
        
        guard try Bcrypt.verify(dto.password ?? "", created: user.passwordHash) else {
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
        response.cookies["token"] = .init(string: token, expires: Date().addingTimeInterval(24 * 60 * 60), isSecure: false, isHTTPOnly: true)
        
        return response
    }
}
