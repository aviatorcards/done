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
        
        // Ensure user has access to the board
        _ = try await req.checkBoardAccess(boardID: dto.boardID)
        
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
        guard let columnID = req.parameters.get("columnID", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        
        let (column, board) = try await req.checkColumnAccess(columnID: columnID)
        
        column.title = dto.title
        if let position = dto.position {
            column.position = position
        }
        try await column.save(on: req.db)
        
        // Broadcast update
        if let boardID = board.id {
            req.application.webSocketManager.broadcast(boardID: boardID, message: "column_updated")
        }
        
        return column
    }

    func delete(req: Request) async throws -> Response {
        guard let columnID = req.parameters.get("columnID", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        
        let (column, board) = try await req.checkColumnAccess(columnID: columnID)
        try req.requireBoardOwner(board: board)
        
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
        let dto = try req.content.decode(ColumnDTO.self)
        guard let columnID = req.parameters.get("columnID", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        
        let (column, board) = try await req.checkColumnAccess(columnID: columnID)
        try req.requireBoardOwner(board: board)
        
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
