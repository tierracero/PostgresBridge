import XCTest
@testable import PostgresBridge

final class PostgresBridgeTests: XCTestCase {
    func testScalarRoundTrip() throws {
        let data = try PostgresDataEncoder().encode("Swift 6.3")
        let value = try PostgresDataDecoder().decode(["name"], String.self, from: data)
        XCTAssertEqual(value, "Swift 6.3")
    }

    func testJSONRoundTrip() throws {
        struct Model: Codable, Equatable {
            let name: String
            let count: Int
        }
        let expected = Model(name: "PostgresBridge", count: 63)
        let data = try PostgresDataEncoder().encode(expected)
        let value = try PostgresDataDecoder().decode(["model"], Model.self, from: data)
        XCTAssertEqual(value, expected)
    }

    func testSQLBindings() throws {
        let prepared = SQL.select("O'Reilly").prepare(.psql).splitted
        XCTAssertEqual(prepared.query, "SELECT $1")
        let data = try PostgresDataEncoder().encode(XCTUnwrap(prepared.values.first))
        XCTAssertEqual(data.string, "O'Reilly")
    }

    func testDatabaseURL() throws {
        let url = try XCTUnwrap(URL(string: "postgres://user:password@localhost:5432/app"))
        let database = try XCTUnwrap(PostgresDatabaseIdentifier(url: url))
        XCTAssertEqual(database.name, "app")
        XCTAssertEqual(database.host.username, "user")
        XCTAssertEqual(database.host.password, "password")
        XCTAssertEqual(try database.host.address().port, 5432)
    }
}
