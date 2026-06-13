import Vapor
import NIO
import NIOCore
import NIOPosix
import NIOConcurrencyHelpers

final class WebSocketManager: Sendable {
    private let app: Application
    private let lock: NIOLock = .init()
    private let connections: NIOLockedValueBox<[UUID: [UUID: (ws: WebSocket, clientId: String?)]]>

    init(app: Application) {
        self.app = app
        self.connections = .init([:])
    }
    
    func connect(boardID: UUID, ws: WebSocket, clientId: String?) {
        let connectionID = UUID()
        self.connections.withLockedValue { dict in
            if dict[boardID] == nil {
                dict[boardID] = [:]
            }
            dict[boardID]?[connectionID] = (ws, clientId)
        }
        
        ws.onClose.whenComplete { _ in
            self.connections.withLockedValue { dict in
                _ = dict[boardID]?.removeValue(forKey: connectionID)
            }
        }
    }
    
    func broadcast(boardID: UUID, message: String, skipClientId: String? = nil) {
        let boardConnections = self.connections.withLockedValue { dict in
            dict[boardID]
        }
        
        boardConnections?.values.forEach { (ws, clientId) in
            if let skip = skipClientId, let cid = clientId, skip == cid {
                return
            }
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
