// import Fluent
// import Vapor

// struct UpdateAdminPassword: AsyncMigration {
//     func prepare(on database: any Database) async throws {
//         let adminEmail = Environment.get("ADMIN_EMAIL") ?? "tristan@fddl.dev"
//         let adminPassword = "CHANGEME"

//         if let admin = try await User.query(on: database)
//             .filter(\.$email == adminEmail)
//             .first()
//         {
//             admin.passwordHash = try Bcrypt.hash(adminPassword)
//             try await admin.save(on: database)
//             print("--- MANUALLY UPDATED ADMIN PASSWORD FOR \(adminEmail) ---")
//         } else {
//             print("--- COULD NOT FIND ADMIN USER \(adminEmail) TO UPDATE PASSWORD ---")
//         }
//     }

//     func revert(on database: any Database) async throws {
//     }
// }
