import Vapor
import JWT

struct AuthMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        let token = request.headers.bearerAuthorization?.token ?? request.cookies["token"]?.string
        
        guard let token = token else {
            throw Abort(.unauthorized)
        }
        
        do {
            let payload = try request.jwt.verify(token, as: UserPayload.self)
            request.auth.login(payload)
        } catch {
            throw Abort(.unauthorized)
        }
        
        return try await next.respond(to: request)
    }
}
