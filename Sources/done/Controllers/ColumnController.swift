import Vapor
import Fluent

struct ColumnController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let columns = routes.grouped("columns").grouped(AuthMiddleware())
        columns.post(use: create)
        columns.group(":columnID") { column in
            column.patch(use: update)
            column.delete(use: delete)
            column.post("move", use: move)
        }
    }

    func create(req: Request) async throws -> Column {
        let dto = try req.content.decode(ColumnDTO.self)
        
        let position: Int
        if let providedPosition = dto.position {
            position = providedPosition
        } else {
            let lastColumn = try await Column.query(on: req.db)
                .filter(\.$board.$id == dto.boardID)
                .sort(\.$position, .descending)
                .first()
            position = (lastColumn?.position ?? -1) + 1
        }
        
        let column = Column(title: dto.title, position: position, boardID: dto.boardID)
        try await column.save(on: req.db)
        return column
    }

    func update(req: Request) async throws -> Column {
        let dto = try req.content.decode(ColumnDTO.self)
        guard let column = try await Column.find(req.parameters.get("columnID"), on: req.db) else {
            throw Abort(.notFound)
        }
        column.title = dto.title
        if let position = dto.position {
            column.position = position
        }
        try await column.save(on: req.db)
        return column
    }

    func delete(req: Request) async throws -> Response {
        let userID = try req.auth.require(UserPayload.self).userID
        guard let column = try await Column.find(req.parameters.get("columnID"), on: req.db) else {
            throw Abort(.notFound)
        }
        
        // Ensure the user owns the board this column belongs to
        let board = try await column.$board.get(on: req.db)
        guard board.$owner.id == userID else {
            throw Abort(.forbidden)
        }
        
        let columnID = try column.requireID()
        
        // Get all cards in this column
        let cards = try await Card.query(on: req.db)
            .filter(\.$column.$id == columnID)
            .all()
        
        let cardIDs = try cards.map { try $0.requireID() }
        
        if !cardIDs.isEmpty {
            // Delete card labels associations
            try await CardLabel.query(on: req.db)
                .filter(\.$card.$id ~~ cardIDs)
                .delete()
                
            // Delete card comments
            try await Comment.query(on: req.db)
                .filter(\.$card.$id ~~ cardIDs)
                .delete()
                
            // Delete cards
            try await Card.query(on: req.db)
                .filter(\.$column.$id == columnID)
                .delete()
        }
        // Broadcast update
        if let boardID = board.id {
            req.application.webSocketManager.broadcast(boardID: boardID, message: "board_updated")
        }
            
        try await column.delete(on: req.db)
        return Response(status: .ok)
    }

    func move(req: Request) async throws -> Response {
        let userID = try req.auth.require(UserPayload.self).userID
        let dto = try req.content.decode(ColumnDTO.self)
        guard let column = try await Column.find(req.parameters.get("columnID"), on: req.db) else {
            throw Abort(.notFound)
        }
        
        let board = try await column.$board.get(on: req.db)
        guard board.$owner.id == userID else {
            throw Abort(.forbidden)
        }
        
        if let position = dto.position {
            column.position = position
            try await column.save(on: req.db)
            
            // Broadcast update
            if let boardID = board.id {
                req.application.webSocketManager.broadcast(boardID: boardID, message: "board_updated")
            }
        }
        
        return Response(status: .ok)
    }
}
