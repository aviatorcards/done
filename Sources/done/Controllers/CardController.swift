import Vapor
import Fluent

struct CardController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let cards = routes.grouped("cards").grouped(AuthMiddleware())
        cards.post(use: create)
        cards.group(":cardID") { card in
            card.patch(use: update)
            card.delete(use: delete)
            card.post("move", use: move)
            card.get("edit", use: edit)
        }
        cards.get("new", use: new)
    }

    func create(req: Request) async throws -> Response {
        let dto = try req.content.decode(CardDTO.self)
        guard let columnID = dto.columnID else { throw Abort(.badRequest) }
        
        // Ensure user has access to the board this column belongs to
        let (_, board) = try await req.checkColumnAccess(columnID: columnID)
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let dueDate = dto.dueDate.flatMap { formatter.date(from: $0) }
        
        let card = Card(
            title: dto.title ?? "",
            description: dto.description ?? "",
            position: dto.position ?? 0,
            dueDate: dueDate,
            priority: dto.priority ?? "medium",
            isCompleted: dto.isCompleted ?? false,
            columnID: columnID,
            assigneeID: dto.assigneeID
        )
        try await card.save(on: req.db)
        
        // Broadcast update
        if let boardID = board.id {
            let clientId = req.headers.first(name: "X-Client-ID")
            req.application.webSocketManager.broadcast(boardID: boardID, message: "board_updated", skipClientId: clientId)
        }
        
        if req.headers.contains(name: "HX-Request") {
            let view = try await req.view.render("partials/card", ["card": card]).get()
            return try await view.encodeResponse(for: req).get()
        }
        
        return try await card.encodeResponse(for: req).get()
    }

    func update(req: Request) async throws -> Response {
        let dto = try req.content.decode(CardDTO.self)
        guard let cardID = req.parameters.get("cardID", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        
        // Ensure user has access to this card
        let (card, _, board) = try await req.checkCardAccess(cardID: cardID)
        
        // Track state change
        let oldIsCompleted = card.isCompleted
        let oldColumnID = card.$column.id
        
        if let title = dto.title { card.title = title }
        if let description = dto.description { card.description = description }
        if let position = dto.position { card.position = position }
        if let priority = dto.priority { card.priority = priority }
        if let dueDateStr = dto.dueDate {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate]
            card.dueDate = formatter.date(from: dueDateStr)
        }
        if let isCompleted = dto.isCompleted { card.isCompleted = isCompleted }
        if let assigneeID = dto.assigneeID { card.$assignee.id = assigneeID }
        
        // AUTO-MOVE LOGIC: If marked as complete, move to "Done" column
        if card.isCompleted && !oldIsCompleted {
            // Search for "Done" or "Completed" column in this board
            let columns = try await Column.query(on: req.db)
                .filter(\.$board.$id == board.requireID())
                .all()
            
            if let targetColumn = columns.first(where: { 
                $0.title.lowercased() == "done" || 
                $0.title.lowercased() == "completed" || 
                $0.title.lowercased() == "finished" 
            }) {
                // Only move if we aren't already in that column
                if targetColumn.id != card.$column.id {
                    card.$column.id = try targetColumn.requireID()
                    
                    // Put it at the top of the "Done" column
                    let otherCards = try await Card.query(on: req.db)
                        .filter(\.$column.$id == targetColumn.requireID())
                        .all()
                    
                    for otherCard in otherCards {
                        otherCard.position += 1
                        try await otherCard.save(on: req.db)
                    }
                    card.position = 0
                }
            }
        }
        
        let columnChanged = card.$column.id != oldColumnID
        try await card.save(on: req.db)
        try await card.$labels.load(on: req.db)
        try await card.$assignee.load(on: req.db)
        
        // Broadcast update
        if let boardID = board.id {
            let clientId = req.headers.first(name: "X-Client-ID")
            req.application.webSocketManager.broadcast(boardID: boardID, message: "board_updated", skipClientId: clientId)
        }
        
        if req.headers.contains(name: "HX-Request") {
            if columnChanged {
                let response = Response(status: .ok)
                response.headers.add(name: "HX-Refresh", value: "true")
                return response
            } else {
                let view = try await req.view.render("partials/card", ["card": card]).get()
                return try await view.encodeResponse(for: req).get()
            }
        }
        
        return try await card.encodeResponse(for: req).get()
    }

    func move(req: Request) async throws -> View {
        let dto = try req.content.decode(CardDTO.self)
        guard let cardID = req.parameters.get("cardID", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        
        // Ensure user has access to this card
        let (card, _, board) = try await req.checkCardAccess(cardID: cardID)
        
        if let columnID = dto.columnID { 
            // If moving to a different column, check access to that column too
            if columnID != card.$column.id {
                let (targetColumn, targetBoard) = try await req.checkColumnAccess(columnID: columnID)
                guard targetBoard.id == board.id else {
                    // Cannot move card between different boards
                    throw Abort(.forbidden)
                }
                card.$column.id = try targetColumn.requireID()
                
                // Automatically toggle isCompleted status based on target column name
                let title = targetColumn.title.lowercased()
                if title == "done" || title == "completed" || title == "finished" || title == "archive" || title == "closed" {
                    card.isCompleted = true
                } else {
                    card.isCompleted = false
                }
            }
        }
        
        if let position = dto.position { card.position = position }
        
        try await card.save(on: req.db)
        try await card.$labels.load(on: req.db)
        try await card.$assignee.load(on: req.db)
        
        // Broadcast update
        if let boardID = board.id {
            let clientId = req.headers.first(name: "X-Client-ID")
            req.application.webSocketManager.broadcast(boardID: boardID, message: "board_updated", skipClientId: clientId)
        }
        
        // After move, return the card fragment for HTMX
        return try await req.view.render("partials/card", [
            "card": card
        ])
    }

    func delete(req: Request) async throws -> Response {
        guard let cardID = req.parameters.get("cardID", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        
        // Ensure user has access and is the OWNER (consistent with current logic)
        let (card, _, board) = try await req.checkCardAccess(cardID: cardID)
        try req.requireBoardOwner(board: board)
        
        // Delete card's labels associations
        try await CardLabel.query(on: req.db)
            .filter(\.$card.$id == cardID)
            .delete()
            
        // Delete card's comments
        try await Comment.query(on: req.db)
            .filter(\.$card.$id == cardID)
            .delete()
            
        // Broadcast update
        if let boardID = board.id {
            let clientId = req.headers.first(name: "X-Client-ID")
            req.application.webSocketManager.broadcast(boardID: boardID, message: "board_updated", skipClientId: clientId)
        }
            
        try await card.delete(on: req.db)
        return Response(status: .ok)
    }

    func new(req: Request) async throws -> View {
        let columnID = try? req.query.get(UUID.self, at: "columnID")
        if let columnID = columnID {
            // Optional check: if they are trying to open the modal for a specific column, check access
            _ = try await req.checkColumnAccess(columnID: columnID)
        }
        return try await req.view.render("partials/card_modal", ["columnID": columnID])
    }

    func edit(req: Request) async throws -> View {
        guard let cardID = req.parameters.get("cardID", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        
        let (card, _, _) = try await req.checkCardAccess(cardID: cardID)
        return try await req.view.render("partials/card_edit_modal", ["card": card])
    }
}
