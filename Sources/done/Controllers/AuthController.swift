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
        throw Abort(.forbidden, reason: "Public registration is currently closed.")
        // Dead code for now...
        let dto = try req.content.decode(UserDTO.self)
        
        guard let password = dto.password, !password.isEmpty else {
            throw Abort(.badRequest, reason: "Password is required")
        }
        
        let passwordHash = try Bcrypt.hash(password)
        let user = User(username: dto.username ?? "", email: dto.email ?? "", passwordHash: passwordHash)
        try await user.save(on: req.db)
        
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
