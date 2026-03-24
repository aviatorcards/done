import Vapor
import JWT

struct AuthMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        let token = request.headers.bearerAuthorization?.token ?? request.cookies["token"]?.string
        
        guard let token = token else {
            if request.headers.first(name: .accept)?.contains("text/html") ?? false && !request.headers.contains(name: "HX-Request") {
                return request.redirect(to: "/")
            }
            throw Abort(.unauthorized)
        }
        
        do {
            let payload = try request.jwt.verify(token, as: UserPayload.self)
            request.auth.login(payload)
        } catch {
            if request.headers.first(name: .accept)?.contains("text/html") ?? false && !request.headers.contains(name: "HX-Request") {
                let response = request.redirect(to: "/")
                response.cookies["token"] = .init(string: "", expires: Date(timeIntervalSince1970: 0), path: "/", isSecure: false, isHTTPOnly: true)
                return response
            }
            throw Abort(.unauthorized)
        }
        
        return try await next.respond(to: request)
    }
}
