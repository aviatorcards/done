@testable import done
import XCTVapor

final class doneTests: XCTestCase {
    var app: Application!

    override func setUp() async throws {
        app = try await Application.make(.testing)
        try await configure(app)
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
}
