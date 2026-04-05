import Vapor
import Fluent

struct AdminController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let admin = routes.grouped(AuthMiddleware())
            .grouped(AdminMiddleware())
            .grouped("admin")
        
        admin.get("invites", use: listInvites)
        admin.post("invites", use: generateManualInvite)
        admin.delete("invites", ":inviteID", use: deleteInvite)
        
        admin.get("users", use: listUsers)
        admin.post("users", ":userID", "reset", use: triggerReset)
        admin.delete("users", ":userID", use: deleteUser)
    }

    func listInvites(req: Request) async throws -> View {
        let invites = try await InviteCode.query(on: req.db)
            .with(\.$inviter)
            .with(\.$board)
            .sort(\.$createdAt, .descending)
            .all()
            
        let user = try req.auth.require(UserPayload.self)
        guard let admin = try await User.find(user.userID, on: req.db) else {
            throw Abort(.unauthorized)
        }
        
        let context: [String: AnySendable] = [
            "title": .init("Admin | Invite Codes"),
            "invites": .init(invites),
            "user": .init(admin)
        ]
        
        return try await req.view.render("admin_invites", context)
    }

    struct ManualInviteDTO: Content {
        var email: String
        var count: String?
    }

    func generateManualInvite(req: Request) async throws -> Response {
        let dto = try req.content.decode(ManualInviteDTO.self)
        let userID = try req.auth.require(UserPayload.self).userID
        
        let count = Int(dto.count ?? "1") ?? 1
        for _ in 0..<count {
            let code = String.generateInviteCode()
            let invite = InviteCode(
                code: code,
                email: dto.email,
                boardID: nil,
                inviterID: userID
            )
            try await invite.save(on: req.db)
        }
        
        if req.headers.contains(name: "HX-Request") {
            let response = Response(status: .noContent)
            response.headers.replaceOrAdd(name: "HX-Refresh", value: "true")
            return response
        }
        
        return req.redirect(to: "/admin/invites")
    }

    func deleteInvite(req: Request) async throws -> Response {
        guard let invite = try await InviteCode.find(req.parameters.get("inviteID"), on: req.db) else {
            throw Abort(.notFound)
        }
        try await invite.delete(on: req.db)
        return Response(status: .ok)
    }

    func listUsers(req: Request) async throws -> View {
        let users = try await User.query(on: req.db)
            .sort(\.$createdAt, .descending)
            .all()
            
        let payload = try req.auth.require(UserPayload.self)
        guard let admin = try await User.find(payload.userID, on: req.db) else {
            throw Abort(.unauthorized)
        }
        
        let context: [String: AnySendable] = [
            "title": .init("Admin | Users"),
            "users": .init(users),
            "user": .init(admin)
        ]
        
        return try await req.view.render("admin_users", context)
    }

    func triggerReset(req: Request) async throws -> Response {
        guard let userToReset = try await User.find(req.parameters.get("userID"), on: req.db) else {
            throw Abort(.notFound)
        }
        
        // Generate a simple secure token
        let token = String.secureRandomString(count: 32)
        userToReset.resetToken = token
        userToReset.resetTokenExpiresAt = Date().addingTimeInterval(24 * 60 * 60) // 24 hours
        try await userToReset.save(on: req.db)
        
        // Send email
        try await req.application.emailService.sendPasswordReset(to: userToReset.email, token: token)
        
        return Response(status: .ok)
    }

    func deleteUser(req: Request) async throws -> Response {
        guard let userToDelete = try await User.find(req.parameters.get("userID"), on: req.db) else {
            throw Abort(.notFound)
        }
        
        let payload = try req.auth.require(UserPayload.self)
        if userToDelete.id == payload.userID {
            throw Abort(.badRequest, reason: "You cannot delete yourself")
        }
        
        try await userToDelete.delete(on: req.db)
        return Response(status: .ok)
    }
}
