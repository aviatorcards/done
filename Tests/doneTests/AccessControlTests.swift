@testable import done
import XCTVapor
import Fluent

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
    
    func testRemoveMember() async throws {
        // 1. Create User A and User B
        let userA = User(username: "userA", email: "a@test.com", passwordHash: "pw")
        let userB = User(username: "userB", email: "b@test.com", passwordHash: "pw")
        try await userA.save(on: app.db)
        try await userB.save(on: app.db)
        
        let userAID = try userA.requireID()
        let userBID = try userB.requireID()
        
        // 2. User A creates a board
        let boardA = Board(title: "Board A", ownerID: userAID)
        try await boardA.save(on: app.db)
        let boardAID = try boardA.requireID()
        
        // 3. User B becomes a member of Board A
        let member = BoardMember(boardID: boardAID, userID: userBID, role: "editor")
        try await member.save(on: app.db)
        
        // Verify User B is a member
        let isMemberBefore = try await BoardMember.query(on: app.db)
            .filter(\BoardMember.$board.$id == boardAID)
            .filter(\BoardMember.$user.$id == userBID)
            .first() != nil
        XCTAssertTrue(isMemberBefore)
        
        // 4. User A removes User B from the board
        let payloadA = UserPayload(subject: "a@test.com", expiration: .init(value: Date.distantFuture), userID: userAID)
        let tokenA = try app.jwt.signers.sign(payloadA)
        
        try await app.test(.DELETE, "boards/\(boardAID)/members/\(userBID)", beforeRequest: { req in
            req.headers.bearerAuthorization = .init(token: tokenA)
        }, afterResponse: { res async in
            XCTAssertEqual(res.status, .ok)
        })
        
        // Verify User B is no longer a member
        let isMemberAfter = try await BoardMember.query(on: app.db)
            .filter(\BoardMember.$board.$id == boardAID)
            .filter(\BoardMember.$user.$id == userBID)
            .first() != nil
        XCTAssertFalse(isMemberAfter)
    }
    
    func testLeaveBoard() async throws {
        // 1. Create User A and User B
        let userA = User(username: "userA", email: "a@test.com", passwordHash: "pw")
        let userB = User(username: "userB", email: "b@test.com", passwordHash: "pw")
        try await userA.save(on: app.db)
        try await userB.save(on: app.db)
        
        let userAID = try userA.requireID()
        let userBID = try userB.requireID()
        
        // 2. User A creates a board
        let boardA = Board(title: "Board A", ownerID: userAID)
        try await boardA.save(on: app.db)
        let boardAID = try boardA.requireID()
        
        // 3. User B becomes a member of Board A
        let member = BoardMember(boardID: boardAID, userID: userBID, role: "editor")
        try await member.save(on: app.db)
        
        // 4. User B attempts to leave the board
        let payloadB = UserPayload(subject: "b@test.com", expiration: .init(value: Date.distantFuture), userID: userBID)
        let tokenB = try app.jwt.signers.sign(payloadB)
        
        try await app.test(.DELETE, "boards/\(boardAID)/members/\(userBID)", beforeRequest: { req in
            req.headers.bearerAuthorization = .init(token: tokenB)
        }, afterResponse: { res async in
            XCTAssertEqual(res.status, .ok)
        })
        
        // Verify User B is no longer a member
        let isMemberAfter = try await BoardMember.query(on: app.db)
            .filter(\BoardMember.$board.$id == boardAID)
            .filter(\BoardMember.$user.$id == userBID)
            .first() != nil
        XCTAssertFalse(isMemberAfter)
    }
    
    func testUnauthorizedRemoveMember() async throws {
        // 1. Create User A, User B, and User C
        let userA = User(username: "userA", email: "a@test.com", passwordHash: "pw")
        let userB = User(username: "userB", email: "b@test.com", passwordHash: "pw")
        let userC = User(username: "userC", email: "c@test.com", passwordHash: "pw")
        try await userA.save(on: app.db)
        try await userB.save(on: app.db)
        try await userC.save(on: app.db)
        
        let userAID = try userA.requireID()
        let userBID = try userB.requireID()
        let userCID = try userC.requireID()
        
        // 2. User A creates a board
        let boardA = Board(title: "Board A", ownerID: userAID)
        try await boardA.save(on: app.db)
        let boardAID = try boardA.requireID()
        
        // 3. User B and User C become members of Board A
        let memberB = BoardMember(boardID: boardAID, userID: userBID, role: "editor")
        let memberC = BoardMember(boardID: boardAID, userID: userCID, role: "editor")
        try await memberB.save(on: app.db)
        try await memberC.save(on: app.db)
        
        // 4. User B attempts to remove User C (forbidden since B is not the owner)
        let payloadB = UserPayload(subject: "b@test.com", expiration: .init(value: Date.distantFuture), userID: userBID)
        let tokenB = try app.jwt.signers.sign(payloadB)
        
        try await app.test(.DELETE, "boards/\(boardAID)/members/\(userCID)", beforeRequest: { req in
            req.headers.bearerAuthorization = .init(token: tokenB)
        }, afterResponse: { res async in
            XCTAssertEqual(res.status, .forbidden)
        })
    }
    
    func testMoveColumnByOwner() async throws {
        // 1. Create User A
        let userA = User(username: "userA", email: "a@test.com", passwordHash: "pw")
        try await userA.save(on: app.db)
        let userAID = try userA.requireID()
        
        // 2. User A creates a board and column
        let boardA = Board(title: "Board A", ownerID: userAID)
        try await boardA.save(on: app.db)
        let boardAID = try boardA.requireID()
        
        let column = Column(title: "Column 1", position: 0, boardID: boardAID)
        try await column.save(on: app.db)
        let columnID = try column.requireID()
        
        // 3. User A moves column
        let payloadA = UserPayload(subject: "a@test.com", expiration: .init(value: Date.distantFuture), userID: userAID)
        let tokenA = try app.jwt.signers.sign(payloadA)
        
        struct MoveDTO: Content {
            var position: Int
        }
        let moveDTO = MoveDTO(position: 5)
        
        try await app.test(.POST, "columns/\(columnID)/move", beforeRequest: { req in
            try req.content.encode(moveDTO)
            req.headers.bearerAuthorization = .init(token: tokenA)
        }, afterResponse: { res async in
            XCTAssertEqual(res.status, .ok)
        })
        
        // Verify position updated
        let updatedColumn = try await Column.find(columnID, on: app.db)
        XCTAssertEqual(updatedColumn?.position, 5)
    }
    
    func testMoveColumnByMember() async throws {
        // 1. Create User A and User B
        let userA = User(username: "userA", email: "a@test.com", passwordHash: "pw")
        let userB = User(username: "userB", email: "b@test.com", passwordHash: "pw")
        try await userA.save(on: app.db)
        try await userB.save(on: app.db)
        
        let userAID = try userA.requireID()
        let userBID = try userB.requireID()
        
        // 2. User A creates a board and column
        let boardA = Board(title: "Board A", ownerID: userAID)
        try await boardA.save(on: app.db)
        let boardAID = try boardA.requireID()
        
        let column = Column(title: "Column 1", position: 0, boardID: boardAID)
        try await column.save(on: app.db)
        let columnID = try column.requireID()
        
        // 3. User B becomes a member of Board A
        let member = BoardMember(boardID: boardAID, userID: userBID, role: "editor")
        try await member.save(on: app.db)
        
        // 4. User B moves column
        let payloadB = UserPayload(subject: "b@test.com", expiration: .init(value: Date.distantFuture), userID: userBID)
        let tokenB = try app.jwt.signers.sign(payloadB)
        
        struct MoveDTO: Content {
            var position: Int
        }
        let moveDTO = MoveDTO(position: 10)
        
        try await app.test(.POST, "columns/\(columnID)/move", beforeRequest: { req in
            try req.content.encode(moveDTO)
            req.headers.bearerAuthorization = .init(token: tokenB)
        }, afterResponse: { res async in
            XCTAssertEqual(res.status, .ok)
        })
        
        // Verify position updated
        let updatedColumn = try await Column.find(columnID, on: app.db)
        XCTAssertEqual(updatedColumn?.position, 10)
    }
}
