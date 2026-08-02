@testable import done
import XCTVapor
import Fluent

final class doneTests: XCTestCase {
    var app: Application!

    override func setUp() async throws {
        app = try await Application.make(.testing)
        try await configure(app)
        try await app.autoRevert()
        try await app.autoMigrate()
    }

    override func tearDown() async throws {
        try await app.asyncShutdown()
    }

    func testHelloWorld() async throws {
        try await app.test(.GET, "hello", afterResponse: { res async in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(res.body.string, "Hello, world!")
        })
    }

    func testPasswordHash() throws {
        let password = "jUwven-3syrsy-rapfef"
        let hash = try Bcrypt.hash(password)
        XCTAssertTrue(try Bcrypt.verify(password, created: hash))
    }

    func testForgotPasswordFlow() async throws {
        // Create user
        let email = "test@example.com"
        let user = User(username: "testuser", email: email, passwordHash: try Bcrypt.hash("password123"))
        try await user.save(on: app.db)

        // Request forgot password
        struct ForgotRequest: Content {
            let email: String
        }
        let requestBody = ForgotRequest(email: email)

        try await app.test(.POST, "forgot-password", beforeRequest: { req in
            try req.content.encode(requestBody)
        }, afterResponse: { res async throws in
            XCTAssertEqual(res.status, .ok)
            let body = try res.content.decode([String: String].self)
            XCTAssertEqual(body["status"], "success")
            XCTAssertNotNil(body["reason"])
        })

        // Check that user token is generated
        let updatedUser = try await User.query(on: app.db).filter(\.$email == email).first()
        XCTAssertNotNil(updatedUser)
        XCTAssertNotNil(updatedUser?.resetToken)
        XCTAssertNotNil(updatedUser?.resetTokenExpiresAt)
        XCTAssertTrue(updatedUser!.resetTokenExpiresAt! > Date())
    }

    func testResetPasswordFlow() async throws {
        // Create user
        let email = "reset@example.com"
        let initialPassword = "oldPassword123"
        let user = User(username: "resetuser", email: email, passwordHash: try Bcrypt.hash(initialPassword))
        let token = "reset-token-xyz"
        user.resetToken = token
        user.resetTokenExpiresAt = Date().addingTimeInterval(3600) // 1 hour
        try await user.save(on: app.db)

        // Request reset
        struct ResetRequest: Content {
            let inviteCode: String
            let password: String
        }
        let newPassword = "newPassword123"
        let requestBody = ResetRequest(inviteCode: token, password: newPassword)

        try await app.test(.POST, "reset-password", beforeRequest: { req in
            try req.content.encode(requestBody)
            req.headers.contentType = .json
        }, afterResponse: { res async throws in
            XCTAssertEqual(res.status, .ok)
            let body = try res.content.decode([String: String].self)
            XCTAssertEqual(body["status"], "success")
            XCTAssertEqual(body["reason"], "Password updated successfully")
        })

        // Check DB state
        let updatedUser = try await User.query(on: app.db).filter(\.$email == email).first()
        XCTAssertNotNil(updatedUser)
        XCTAssertNil(updatedUser?.resetToken)
        XCTAssertNil(updatedUser?.resetTokenExpiresAt)
        XCTAssertTrue(try Bcrypt.verify(newPassword, created: updatedUser!.passwordHash))

        // Check Login with new password
        struct LoginRequest: Content {
            let email: String
            let password: String
        }
        let loginBody = LoginRequest(email: email, password: newPassword)
        try await app.test(.POST, "auth/login", beforeRequest: { req in
            try req.content.encode(loginBody)
        }, afterResponse: { res async throws in
            XCTAssertEqual(res.status, .ok)
            let body = try res.content.decode([String: String].self)
            XCTAssertNotNil(body["token"])
        })
    }
}
