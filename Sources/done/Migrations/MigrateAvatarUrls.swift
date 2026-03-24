import Fluent

struct MigrateAvatarUrls: AsyncMigration {
    func prepare(on database: any Database) async throws {
        // Find all users with the old /uploads/avatars/ prefix
        let users = try await User.query(on: database)
            .all()
            
        for user in users {
            if let url = user.avatarUrl, url.hasPrefix("/uploads/avatars/") {
                user.avatarUrl = url.replacingOccurrences(of: "/uploads/avatars/", with: "/api/users/avatar/")
                try await user.save(on: database)
            }
        }
    }

    func revert(on database: any Database) async throws {
        let users = try await User.query(on: database)
            .all()
            
        for user in users {
            if let url = user.avatarUrl, url.hasPrefix("/api/users/avatar/") {
                user.avatarUrl = url.replacingOccurrences(of: "/api/users/avatar/", with: "/uploads/avatars/")
                try await user.save(on: database)
            }
        }
    }
}
