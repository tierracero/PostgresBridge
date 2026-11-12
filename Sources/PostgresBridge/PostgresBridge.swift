import NIO
import NIOConcurrencyHelpers
import PostgresNIO
import AsyncKit
import Bridges
import Logging

public struct PostgresBridge: ContextBridgeable {
    public let context: BridgeWithContext<PBR>
    
    init (_ context: BridgeWithContext<PBR>) {
        self.context = context
    }
    
    /// Gives a connection to the database and releases it automatically in both success and error cases
    public func connection<T>(to db: DatabaseIdentifier,
                                            _ closure: @escaping (PostgresConnection) -> EventLoopFuture<T>) -> EventLoopFuture<T> {
        context.bridge.connection(to: db, on: context.eventLoop, closure)
    }
    
    /// Gives a connection to the database and you should close it by yourself
    public func requestConnection(to db: DatabaseIdentifier) -> EventLoopFuture<PostgresConnection> {
        context.bridge.requestConnection(to: db, on: context.eventLoop)
    }
    
    public func transaction<T>(to db: DatabaseIdentifier,
                                            _ closure: @escaping (PostgresConnection) -> EventLoopFuture<T>) -> EventLoopFuture<T> {
        context.bridge.transaction(to: db, on: context.eventLoop, closure)
    }
    
    public func register(_ db: DatabaseIdentifier) {
        context.bridge.register(db)
    }
    
    public func migrator(for db: DatabaseIdentifier, dedicatedSchema: Bool = false) -> Migrator {
        BridgeDatabaseMigrations<PBR>(context.bridge, db: db, dedicatedSchema: dedicatedSchema)
    }
}

/// Bridges serializes registry operations with `poolsLock`. The registry storage also
/// protects direct access through the legacy `pools` property.
public final class PBR: Bridgeable, Sendable {
    public typealias Source = PostgresConnectionSource
    public typealias Database = PostgresDatabase
    public typealias Connection = PostgresConnection
    
    public static var dialect: SQLDialect { .psql }
    
    private let poolRegistry = PostgresPoolRegistry()

    /// A synchronized snapshot of the registry. Use `register` and `pool` for atomic
    /// lookup and creation; modifying a snapshot is not an atomic registry operation.
    public var pools: [String: GroupPool] {
        get { poolRegistry.snapshot() }
        set { poolRegistry.replace(with: newValue) }
    }
    public let poolsLock = NIOLock()
    
    public let logger: Logger
    public let eventLoopGroup: EventLoopGroup
    
    public required init (eventLoopGroup: EventLoopGroup, logger: Logger) {
        self.eventLoopGroup = eventLoopGroup
        self.logger = logger
    }

    /// Re-registering a database must not discard a live pool without shutting it down.
    public func register(_ db: DatabaseIdentifier) {
        poolsLock.withLock {
            guard pools[db.key] == nil else { return }
            pools[db.key] = GroupPool(
                source: .init(db),
                maxConnectionsPerEventLoop: db.maxConnectionsPerEventLoop,
                logger: logger,
                on: eventLoopGroup
            )
        }
    }
    
    /// Gives a connection to the database and releases it automatically in both success and error cases
    public func connection<T>(to db: DatabaseIdentifier,
                                  on eventLoop: EventLoop,
                                  _ closure: @escaping (PostgresConnection) -> EventLoopFuture<T>) -> EventLoopFuture<T> {
        self.db(db, on: eventLoop).withConnection { closure($0) }
    }
    
    /// Gives a connection to the database and you should close it by yourself
    public func requestConnection(to db: DatabaseIdentifier, on eventLoop: EventLoop) -> EventLoopFuture<PostgresConnection> {
        _db(db, on: eventLoop).requestConnection()
    }
    
    public func db(_ db: DatabaseIdentifier, on eventLoop: EventLoop) -> PostgresDatabase {
        _db(db, on: eventLoop)
    }
    
    private func _db(_ db: DatabaseIdentifier, on eventLoop: EventLoop) -> _ConnectionPoolPostgresDatabase {
        _ConnectionPoolPostgresDatabase(pool: pool(db, for: eventLoop), logger: logger)
    }
    
    deinit {
        // A Sendable bridge may lose its last reference on an event-loop thread.
        // AsyncKit's synchronous shutdown waits and must not run on that thread.
        let registeredPools = poolsLock.withLock { Array(pools.values) }
        registeredPools.forEach { $0.shutdownGracefully { _ in } }
    }
}

/// AsyncKit's group pools are designed for use from multiple threads, but do not
/// declare Sendable. Their per-event-loop pools schedule work on their owning loop.
/// The unchecked assertion is limited to this storage boundary: every dictionary
/// access takes `lock`, and only AsyncKit's public pool APIs may operate on its values.
/// This lock is separate from `PBR.poolsLock` because Bridges holds that lock while
/// calling the `pools` getter/setter. Always acquire the outer lock first.
private final class PostgresPoolRegistry: @unchecked Sendable {
    private let lock = NIOLock()
    private var storage: [String: PBR.GroupPool] = [:]

    func snapshot() -> [String: PBR.GroupPool] {
        lock.withLock { storage }
    }

    func replace(with pools: [String: PBR.GroupPool]) {
        lock.withLock { storage = pools }
    }
}

// MARK: Database on pool

// AsyncKit has not annotated this pool as Sendable. These methods exclusively use
// its public APIs, which schedule mutable connection state on the owning event loop.
private struct _ConnectionPoolPostgresDatabase: @unchecked Sendable {
    let pool: EventLoopConnectionPool<PostgresConnectionSource>
    let logger: Logger
}

extension _ConnectionPoolPostgresDatabase: PostgresDatabase {
    var eventLoop: EventLoop { self.pool.eventLoop }
    
    func send(_ request: PostgresRequest, logger: Logger) -> EventLoopFuture<Void> {
        pool.withConnection(logger: logger) {
            $0.send(request, logger: logger)
        }
    }
    
    func withConnection<T>(_ closure: @escaping (PostgresConnection) -> EventLoopFuture<T>) -> EventLoopFuture<T> {
        pool.withConnection(logger: self.logger, closure)
    }
    
    func requestConnection() -> EventLoopFuture<PostgresConnection> {
        pool.requestConnection(logger: logger)
    }
}
