@testable import done
import XCTVapor

final class AccessControlTests: XCTestCase {
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
    
    func testUnauthorizedCardCreation() async throws {
        // 1. Create User A and User B
        let userA = User(username: "userA", email: "a@test.com", passwordHash: "pw")
        let userB = User(username: "userB", email: "b@test.com", passwordHash: "pw")
        try await userA.save(on: app.db)
        try await userB.save(on: app.db)
        
        // 2. User A creates a board and a column
        let boardA = Board(title: "Board A", ownerID: try userA.requireID())
        try await boardA.save(on: app.db)
        let columnA = Column(title: "Column A", position: 0, boardID: try boardA.requireID())
        try await columnA.save(on: app.db)
        
        // 3. User B attempts to create a card in User A's column
        let payload = UserPayload(subject: "b@test.com", expiration: .init(value: Date.distantFuture), userID: try userB.requireID())
        let tokenB = try app.jwt.signers.sign(payload)
        
        let cardDTO = CardDTO(title: "Hacked Card", columnID: try columnA.requireID())
        
        try await app.test(.POST, "cards", beforeRequest: { req in
            try req.content.encode(cardDTO)
            req.headers.bearerAuthorization = .init(token: tokenB)
        }, afterResponse: { res async in
            XCTAssertEqual(res.status, .forbidden)
        })
    }
    
    func testUnauthorizedColumnUpdate() async throws {
        // 1. Create User A and User B
        let userA = User(username: "userA", email: "a@test.com", passwordHash: "pw")
        let userB = User(username: "userB", email: "b@test.com", passwordHash: "pw")
        try await userA.save(on: app.db)
        try await userB.save(on: app.db)
        
        // 2. User A creates a board and a column
        let boardA = Board(title: "Board A", ownerID: try userA.requireID())
        try await boardA.save(on: app.db)
        let columnA = Column(title: "Column A", position: 0, boardID: try boardA.requireID())
        try await columnA.save(on: app.db)
        
        // 3. User B attempts to update User A's column
        let payload = UserPayload(subject: "b@test.com", expiration: .init(value: Date.distantFuture), userID: try userB.requireID())
        let tokenB = try app.jwt.signers.sign(payload)
        
        let columnDTO = ColumnDTO(title: "Hacked Column", boardID: try boardA.requireID())
        
        try await app.test(.PATCH, "columns/\(try columnA.requireID())", beforeRequest: { req in
            try req.content.encode(columnDTO)
            req.headers.bearerAuthorization = .init(token: tokenB)
        }, afterResponse: { res async in
            XCTAssertEqual(res.status, .forbidden)
        })
    }
}
