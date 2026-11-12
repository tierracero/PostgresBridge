import Dispatch
import NIOConcurrencyHelpers
import XCTest
@testable import PostgresBridge

final class PoolConcurrencyTests: XCTestCase {
    func testBridgeCanBeReleasedOnItsEventLoop() throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try! group.syncShutdownGracefully() }
        try group.next().submit {
            let bridge = PBR(eventLoopGroup: group, logger: Logger(label: "pool-deinit-test"))
            bridge.register(makeDatabase())
            // Deinit runs on this event loop and must not synchronously wait for it.
        }.wait()
    }

    func testConcurrentRegistrationLookupAndSnapshotsShareOnePool() throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 2)
        let bridge = PBR(eventLoopGroup: group, logger: Logger(label: "pool-concurrency-test"))
        defer {
            bridge.shutdown()
            try! group.syncShutdownGracefully()
        }
        // Compile-time check that PBR has a Sendable conformance.
        requireSendable(bridge)
        let loop = group.next()
        let identities = NIOLockedValueBox<[ObjectIdentifier]>([])

        DispatchQueue.concurrentPerform(iterations: 300) { iteration in
            // DatabaseIdentifier is not Sendable: each worker owns its own instance.
            let database = makeDatabase()
            if iteration.isMultiple(of: 2) { bridge.register(database) }
            let pool = bridge.pool(database, for: loop)
            identities.withLockedValue { $0.append(ObjectIdentifier(pool)) }
            _ = bridge.pools.count
        }

        XCTAssertEqual(bridge.pools.count, 1)
        XCTAssertEqual(identities.withLockedValue { Set($0).count }, 1)
    }

    func testLegacyPropertyAccessAlsoUsesSynchronizedStorage() throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let bridge = PBR(eventLoopGroup: group, logger: Logger(label: "pool-snapshot-test"))
        defer {
            bridge.shutdown()
            try! group.syncShutdownGracefully()
        }
        bridge.register(makeDatabase())
        let original = try XCTUnwrap(bridge.pools["concurrency_test"])
        DispatchQueue.concurrentPerform(iterations: 300) { iteration in
            if iteration.isMultiple(of: 2) {
                // Reassign the same registry contents while other threads read them.
                bridge.pools = bridge.pools
            } else {
                _ = bridge.pools["concurrency_test"]
            }
        }
        XCTAssertTrue(bridge.pools["concurrency_test"] === original)
    }
}

private func requireSendable<T: Sendable>(_ value: T) {}

private func makeDatabase() -> DatabaseIdentifier {
    .psql(
        name: "concurrency_test",
        host: .init(hostname: "localhost", port: 5432, username: "test", password: nil)
    )
}
