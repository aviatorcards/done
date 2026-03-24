import Vapor
import Fluent

struct AdminMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        guard let payload = request.auth.get(UserPayload.self) else {
            throw Abort(.unauthorized)
        }

        guard let user = try await User.find(payload.userID, on: request.db) else {
            throw Abort(.unauthorized)
        }
        
        guard user.isAdmin else {
            throw Abort(.forbidden, reason: "Admin access required.")
        }
        
        return try await next.respond(to: request)
    }
}
