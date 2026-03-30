// import Fluent
// import Vapor

// struct SeedAdmin: AsyncMigration {
//     func prepare(on database: any Database) async throws {
//         let adminEmail = Environment.get("ADMIN_EMAIL") ?? "tristan@fddl.dev"
//         let adminPassword = "CHANGEME"

//         let existingAdmin = try await User.query(on: database)
//             .filter(\.$email == adminEmail)
//             .first()

//         if let admin = existingAdmin {
//             admin.passwordHash = try Bcrypt.hash(adminPassword)
//             admin.isAdmin = true
//             try await admin.save(on: database)
//             print("--- UPDATED ADMIN PASSWORD: \(adminEmail) ---")
//         } else {
//             let passwordHash = try Bcrypt.hash(adminPassword)
//             let admin = User(
//                 id: UUID(uuidString: "00000000-0000-0000-0000-000000000001"),
//                 username: "admin",
//                 email: adminEmail,
//                 passwordHash: passwordHash,
//                 isAdmin: true,
//                 displayName: "Administrator"
//             )
//             try await admin.save(on: database)
//             print("--- SEEDED ADMIN USER (Fixed ID): \(adminEmail) ---")
//         }
//     }

//     func revert(on database: any Database) async throws {
//         // We don't necessarily want to delete the admin on revert
//     }
// }
