import Vapor
import Fluent

struct AdminMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        let payload = try request.auth.require(UserPayload.self)
        guard let user = try await User.find(payload.userID, on: request.db), user.isAdmin else {
            throw Abort(.forbidden, reason: "Admin access required.")
        }
        return try await next.respond(to: request)
    }
}
