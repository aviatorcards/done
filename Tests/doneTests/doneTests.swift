@testable import done
import XCTVapor

final class doneTests: XCTestCase {
    func testHelloWorld() throws {
        let app = Application(.testing)
        defer { app.shutdown() }
        try configure(app)

        try app.test(.GET, "hello", afterResponse: { res in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(res.body.string, "Hello, world!")
        })
    func testPasswordHash() throws {
        let hash = "$2b$12$L0sp5Re0PWcMz1alVI8hkeVveH/y8JXW/fPi/mNoXykctld4Az3v2"
        let password = "jUwven-3syrsy-rapfef"
        XCTAssertTrue(try Bcrypt.verify(password, created: hash))
    }
}
