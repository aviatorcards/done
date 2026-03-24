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
        var count: Int?
    }

    func generateManualInvite(req: Request) async throws -> Response {
        let dto = try req.content.decode(ManualInviteDTO.self)
        let userID = try req.auth.require(UserPayload.self).userID
        
        let count = dto.count ?? 1
        for _ in 0..<count {
            let code = String((0..<8).map { _ in "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789".randomElement()! })
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
}
