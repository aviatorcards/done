import Vapor
import Fluent

struct BoardController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let boards = routes.grouped("boards").grouped(AuthMiddleware())
        boards.get(use: index)
        boards.post(use: create)
        boards.post("import", use: importBoard)
        boards.group(":boardID") { board in
            board.get(use: show)
            board.patch(use: update)
            board.delete(use: delete)
            board.post("members", use: inviteMember)
        }
    }

    struct InviteDTO: Content {
        var email: String
    }

    func inviteMember(req: Request) async throws -> Response {
        let userID = try req.auth.require(UserPayload.self).userID
        guard let inviter = try await User.find(userID, on: req.db) else {
            throw Abort(.unauthorized)
        }
        
        guard let board = try await Board.find(req.parameters.get("boardID"), on: req.db) else {
             throw Abort(.notFound)
        }
        
        // Ensure the current user is the owner
        guard board.$owner.id == userID else {
            throw Abort(.forbidden)
        }
        
        let inviteDTO = try req.content.decode(InviteDTO.self)
        let invitee = try await User.query(on: req.db).filter(\.$email == inviteDTO.email).first()
        
        if let invitee = invitee {
            // User exists
            if invitee.id == userID {
                throw Abort(.badRequest, reason: "You are already the owner of this board.")
            }
            
            let isMember = try await board.$members.query(on: req.db).filter(\User.$id == invitee.requireID()).first() != nil
            if isMember {
                throw Abort(.conflict, reason: "User is already a member.")
            }
            
            let member = try BoardMember(boardID: board.requireID(), userID: invitee.requireID(), role: "editor")
            try await member.save(on: req.db)
            
            // Send notification email
            try await req.application.emailService.sendInvite(
                to: inviteDTO.email,
                code: "ALREADY_MEMBER",
                boardTitle: board.title,
                inviterName: inviter.username
            )
        } else {
            // User doesn't exist, create invite code
            let code = String.generateInviteCode()
            let inviteRecord = try InviteCode(
                code: code,
                email: inviteDTO.email,
                boardID: board.requireID(),
                inviterID: userID
            )
            try await inviteRecord.save(on: req.db)
            
            // Send invite email
            try await req.application.emailService.sendInvite(
                to: inviteDTO.email,
                code: code,
                boardTitle: board.title,
                inviterName: inviter.username
            )
        }
        
        return Response(status: .ok)
    }

    func update(req: Request) async throws -> Board {
        let userID = try req.auth.require(UserPayload.self).userID
        guard let board = try await Board.find(req.parameters.get("boardID"), on: req.db) else {
            throw Abort(.notFound)
        }
        
        // Ensure the user owns the board
        guard board.$owner.id == userID else {
            throw Abort(.forbidden)
        }
        
        let dto = try req.content.decode(BoardDTO.self)
        board.title = dto.title
        try await board.save(on: req.db)
        
        // Broadcast update
        if let boardID = board.id {
            req.application.webSocketManager.broadcast(boardID: boardID, message: "board_updated")
        }
        
        return board
    }


    func importBoard(req: Request) async throws -> Response {
        let userID = try req.auth.require(UserPayload.self).userID
        let importRequest = try req.content.decode(ImportBoardDTO.self)
        
        let service = KanbanImportService()
        let board = try await service.importToDatabase(req: req, markdown: importRequest.markdown, ownerID: userID)
        
        return req.redirect(to: "/boards/\(try board.requireID())")
    }

    func index(req: Request) async throws -> View {
        let userID = try req.auth.require(UserPayload.self).userID
        guard let user = try await User.find(userID, on: req.db) else {
            throw Abort(.unauthorized)
        }
        
        let ownedBoards = try await user.$boards.query(on: req.db)
            .with(\.$owner)
            .with(\.$members)
            .all()
            
        let sharedBoards = try await user.$sharedBoards.query(on: req.db)
            .with(\.$owner)
            .with(\.$members)
            .all()
            
        let boards = (ownedBoards + sharedBoards).sorted(by: { ($0.updatedAt ?? $0.createdAt ?? Date()) > ($1.updatedAt ?? $1.createdAt ?? Date()) })
        
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
        
        // Ensure the user owns the board OR is a member
        let isOwner = board.$owner.id == userID
        let isMember = try await board.$members.query(on: req.db).filter(\User.$id == userID).first() != nil
        
        guard isOwner || isMember else {
            throw Abort(.forbidden)
        }
        
        try await board.$members.load(on: req.db)
        
        let context: [String: AnySendable] = [
            "title": .init(board.title),
            "board": .init(board),
            "columns": .init(columns),
            "user": .init(user)
        ]
        
        return try await req.view.render("board", context)
    }

    func delete(req: Request) async throws -> Response {
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
        return Response(status: .ok)
    }
}
