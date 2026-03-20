import Vapor
import Fluent

struct UserController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let users = routes.grouped(AuthMiddleware())
            .grouped("users")
        
        users.patch("profile", use: updateProfile)
        users.post("avatar", use: uploadAvatar)
    }

    func updateProfile(req: Request) async throws -> UserDTO.Public {
        let updateData = try req.content.decode(UserDTO.self)
        let payload = try req.auth.require(UserPayload.self)
        
        guard let user = try await User.find(payload.userID, on: req.db) else {
            throw Abort(.notFound)
        }

        if let newPassword = updateData.newPassword {
            guard let currentPassword = updateData.currentPassword else {
                throw Abort(.badRequest, reason: "Current password required to set a new one")
            }
            
            guard try Bcrypt.verify(currentPassword, created: user.passwordHash) else {
                throw Abort(.unauthorized, reason: "Incorrect current password")
            }
            
            user.passwordHash = try Bcrypt.hash(newPassword)
        }

        try await user.save(on: req.db)
        return user.toPublic()
    }

    func uploadAvatar(req: Request) async throws -> UserDTO.Public {
        let payload = try req.auth.require(UserPayload.self)
        guard let user = try await User.find(payload.userID, on: req.db) else {
            throw Abort(.notFound)
        }

        struct UploadData: Content {
            var avatar: File
        }
        let data = try req.content.decode(UploadData.self)

        let filename = "\(payload.userID.uuidString)-\(Int(Date().timeIntervalSince1970)).\(data.avatar.extension ?? "jpg")"
        let path = req.application.directory.publicDirectory + "uploads/avatars/" + filename
        
        // Ensure directory exists
        try await req.fileio.writeFile(data.avatar.data, at: path)
        
        user.avatarUrl = "/uploads/avatars/" + filename
        try await user.save(on: req.db)
        
        return user.toPublic()
    }
}
