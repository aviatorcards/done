// import Fluent
// import Vapor

// struct SeedAdmin: AsyncMigration {
//     func prepare(on database: any Database) async throws {
//         let adminEmail = Environment.get("ADMIN_EMAIL") ?? "[EMAIL_ADDRESS]"
//         let adminPassword = Environment.get("ADMIN_PASSWORD") ?? "[PASSWORD]" // LMAO

//         let existingAdmin = try await User.query(on: database)
//             .filter(\.$isAdmin == true)
//             .first()

//         if existingAdmin == nil {
//             let passwordHash = try Bcrypt.hash(adminPassword)
//             let admin = User(
//                 username: "admin",
//                 email: adminEmail,
//                 passwordHash: passwordHash,
//                 isAdmin: true,
//                 displayName: "Administrator"
//             )
//             try await admin.save(on: database)
//             print("--- SEEDED ADMIN USER: \(adminEmail) / \(adminPassword) ---")
//         }
//     }

//     func revert(on database: any Database) async throws {
//         // We don't necessarily want to delete the admin on revert,
//         // as they might have created content.
//     }
// }
