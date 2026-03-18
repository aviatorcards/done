import Vapor
import Fluent

struct BoardController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let boards = routes.grouped("boards").grouped(AuthMiddleware())
        boards.get(use: index)
        boards.post(use: create)
        boards.group(":boardID") { board in
            board.get(use: show)
            board.delete(use: delete)
        }
    }

    func index(req: Request) async throws -> View {
        let userID = try req.auth.require(UserPayload.self).userID
        guard let user = try await User.find(userID, on: req.db) else {
            throw Abort(.unauthorized)
        }
        
        let boards: [Board] = try await Board.query(on: req.db)
            .filter(\Board.$owner.$id == userID)
            .with(\.$owner)
            .all()
        
        let context: [String: AnySendable] = [
            "title": .init("My Boards"),
            "boards": .init(boards),
            "user": .init(user)
        ]
        
        if req.headers.contains(name: "HX-Request") {
            return try await req.view.render("partials/board_list", context)
        }
        
        return try await req.view.render("index", context)
    }

    func create(req: Request) async throws -> Board {
        let userID = try req.auth.require(UserPayload.self).userID
        let dto = try req.content.decode(BoardDTO.self)
        let board = Board(title: dto.title, ownerID: userID)
        try await board.save(on: req.db)
        
        // Add default columns
        let todo = Column(title: "To Do", position: 0, boardID: try board.requireID())
        let inProgress = Column(title: "In Progress", position: 1, boardID: try board.requireID())
        let done = Column(title: "Done", position: 2, boardID: try board.requireID())
        
        try await [todo, inProgress, done].create(on: req.db)
        
        return board
    }

    func show(req: Request) async throws -> View {
        guard let board = try await Board.find(req.parameters.get("boardID"), on: req.db) else {
            throw Abort(.notFound)
        }
        
        // Load columns and cards
        try await board.$owner.load(on: req.db)
        guard let boardID = board.id else { throw Abort(.internalServerError) }
        
        let columns: [Column] = try await Column.query(on: req.db)
            .filter(\Column.$board.$id == boardID)
            .with(\Column.$cards) { card in
                card.with(\.$labels)
            }
            .sort(\Column.$position, .ascending)
            .all()
        
        let userID = try req.auth.require(UserPayload.self).userID
        guard let user = try await User.find(userID, on: req.db) else {
            throw Abort(.unauthorized)
        }
        
        let context: [String: AnySendable] = [
            "title": .init(board.title),
            "board": .init(board),
            "columns": .init(columns),
            "user": .init(user)
        ]
        
        return try await req.view.render("board", context)
    }

    func delete(req: Request) async throws -> HTTPStatus {
        let userID = try req.auth.require(UserPayload.self).userID
        guard let board = try await Board.find(req.parameters.get("boardID"), on: req.db) else {
            throw Abort(.notFound)
        }
        
        // Ensure the user owns the board
        guard board.$owner.id == userID else {
            throw Abort(.forbidden)
        }
        
        let boardID = try board.requireID()
        
        // Get all columns in this board
        let columns = try await Column.query(on: req.db)
            .filter(\.$board.$id == boardID)
            .all()
        
        let columnIDs = try columns.map { try $0.requireID() }
        
        if !columnIDs.isEmpty {
            // Get all cards in these columns
            let cards = try await Card.query(on: req.db)
                .filter(\.$column.$id ~~ columnIDs)
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
                    .filter(\.$column.$id ~~ columnIDs)
                    .delete()
            }
            
            // Delete columns
            try await Column.query(on: req.db)
                .filter(\.$board.$id == boardID)
                .delete()
        }
        // Broadcast update
        req.application.webSocketManager.broadcast(boardID: boardID, message: "board_deleted")
            
        try await board.delete(on: req.db)
        return .noContent
    }
}
