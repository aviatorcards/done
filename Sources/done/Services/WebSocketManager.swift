import Vapor
import NIO
import NIOCore
import NIOPosix
import NIOConcurrencyHelpers

final class WebSocketManager: Sendable {
    private let app: Application
    private let lock: NIOLock = .init()
    private let connections: NIOLockedValueBox<[UUID: [UUID: WebSocket]]>

    init(app: Application) {
        self.app = app
        self.connections = .init([:])
    }
    
    func connect(boardID: UUID, ws: WebSocket) {
        let connectionID = UUID()
        self.connections.withLockedValue { dict in
            if dict[boardID] == nil {
                dict[boardID] = [:]
            }
            dict[boardID]?[connectionID] = ws
        }
        
        ws.onClose.whenComplete { _ in
            self.connections.withLockedValue { dict in
                _ = dict[boardID]?.removeValue(forKey: connectionID)
            }
        }
    }
    
    func broadcast(boardID: UUID, message: String) {
        let boardConnections = self.connections.withLockedValue { dict in
            dict[boardID]
        }
        
        boardConnections?.values.forEach { ws in
            ws.send(message)
        }
    }
}

extension Application {
    struct WebSocketManagerKey: StorageKey {
        typealias Value = WebSocketManager
    }
    
    var webSocketManager: WebSocketManager {
        if let manager = self.storage[WebSocketManagerKey.self] {
            return manager
        } else {
            let manager = WebSocketManager(app: self)
            self.storage[WebSocketManagerKey.self] = manager
            return manager
        }
    }
}
