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

    func create(req: Request) async throws -> Card {
        let dto = try req.content.decode(CardDTO.self)
        guard let columnID = dto.columnID else { throw Abort(.badRequest) }
        
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
        return card
    }

    func update(req: Request) async throws -> Card {
        let dto = try req.content.decode(CardDTO.self)
        guard let card = try await Card.find(req.parameters.get("cardID"), on: req.db) else {
            throw Abort(.notFound)
        }
        
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
        
        try await card.save(on: req.db)
        return card
    }

    func move(req: Request) async throws -> View {
        let dto = try req.content.decode(CardDTO.self)
        guard let card = try await Card.find(req.parameters.get("cardID"), on: req.db) else {
            throw Abort(.notFound)
        }
        
        if let columnID = dto.columnID { card.$column.id = columnID }
        if let position = dto.position { card.position = position }
        
        try await card.save(on: req.db)
        try await card.$labels.load(on: req.db)
        
        // Broadcast update
        let board = try await card.$column.get(on: req.db).$board.get(on: req.db)
        if let boardID = board.id {
            req.application.webSocketManager.broadcast(boardID: boardID, message: "board_updated")
        }
        
        // After move, return the card fragment for HTMX
        return try await req.view.render("partials/card", [
            "card": card
        ])
    }

    func delete(req: Request) async throws -> Response {
        let userID = try req.auth.require(UserPayload.self).userID
        guard let card = try await Card.find(req.parameters.get("cardID"), on: req.db) else {
            throw Abort(.notFound)
        }
        
        // Ensure the user owns the board this card belongs to
        let column = try await card.$column.get(on: req.db)
        let board = try await column.$board.get(on: req.db)
        guard board.$owner.id == userID else {
            throw Abort(.forbidden)
        }
        
        let cardID = try card.requireID()
        
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
            req.application.webSocketManager.broadcast(boardID: boardID, message: "board_updated")
        }
            
        try await card.delete(on: req.db)
        return Response(status: .ok)
    }

    func new(req: Request) async throws -> View {
        let columnID = try? req.query.get(UUID.self, at: "columnID")
        return try await req.view.render("partials/card_modal", ["columnID": columnID])
    }

    func edit(req: Request) async throws -> View {
        guard let card = try await Card.find(req.parameters.get("cardID"), on: req.db) else {
            throw Abort(.notFound)
        }
        return try await req.view.render("partials/card_edit_modal", ["card": card])
    }
}
