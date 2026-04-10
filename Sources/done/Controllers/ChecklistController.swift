import Vapor
import Fluent

struct ChecklistDTO: Content {
    let title: String
}

struct ChecklistItemDTO: Content {
    let content: String?
    let isCompleted: Bool?
    let position: Int?
}

struct ChecklistItemCreateDTO: Content {
    let content: String
    let position: Int?
}

struct ChecklistController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let authRoutes = routes.grouped(AuthMiddleware())
        
        let checklists = authRoutes.grouped("api", "checklists")
        checklists.get(use: getChecklists)
        checklists.post(use: createChecklist)
        checklists.delete(":checklistID", use: deleteChecklist)
        
        let items = authRoutes.grouped("api", "checklist-items")
        items.post(":checklistID", use: createItem)
        items.patch(":itemID", use: updateItem)
        items.delete(":itemID", use: deleteItem)
    }

    func getChecklists(req: Request) async throws -> [ChecklistResponseDTO] {
        let userID = try req.auth.require(UserPayload.self).userID
        let checklists = try await Checklist.query(on: req.db)
            .filter(\.$owner.$id == userID)
            .with(\.$items)
            .all()
            
        return checklists.map { checklist in
            let items = (checklist.$items.value ?? []).sorted(by: { $0.position < $1.position })
            return ChecklistResponseDTO(
                id: checklist.id,
                title: checklist.title,
                items: items.map { ChecklistItemResponseDTO(id: $0.id, content: $0.content, isCompleted: $0.isCompleted, position: $0.position) }
            )
        }
    }

    func createChecklist(req: Request) async throws -> ChecklistResponseDTO {
        let userID = try req.auth.require(UserPayload.self).userID
        let dto = try req.content.decode(ChecklistDTO.self)
        
        let checklist = Checklist(title: dto.title, ownerID: userID)
        try await checklist.save(on: req.db)
        
        return ChecklistResponseDTO(
            id: checklist.id,
            title: checklist.title,
            items: []
        )
    }

    func deleteChecklist(req: Request) async throws -> Response {
        let userID = try req.auth.require(UserPayload.self).userID
        guard let checklistID = req.parameters.get("checklistID", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        guard let checklist = try await Checklist.find(checklistID, on: req.db) else {
            throw Abort(.notFound)
        }
        
        guard checklist.$owner.id == userID else {
            throw Abort(.forbidden)
        }
        
        try await checklist.delete(on: req.db)
        return Response(status: .ok)
    }
    
    func createItem(req: Request) async throws -> ChecklistItem {
        let userID = try req.auth.require(UserPayload.self).userID
        let dto = try req.content.decode(ChecklistItemCreateDTO.self)
        guard let checklistID = req.parameters.get("checklistID", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        guard let checklist = try await Checklist.find(checklistID, on: req.db) else {
            throw Abort(.notFound)
        }
        
        guard checklist.$owner.id == userID else {
            throw Abort(.forbidden)
        }
        
        let item = ChecklistItem(
            content: dto.content,
            isCompleted: false,
            position: dto.position ?? 0,
            checklistID: checklistID
        )
        try await item.save(on: req.db)
        
        return item
    }

    func updateItem(req: Request) async throws -> ChecklistItem {
        let userID = try req.auth.require(UserPayload.self).userID
        let dto = try req.content.decode(ChecklistItemDTO.self)
        guard let itemID = req.parameters.get("itemID", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        guard let item = try await ChecklistItem.find(itemID, on: req.db) else {
            throw Abort(.notFound)
        }
        
        let checklist = try await item.$checklist.get(on: req.db)
        guard checklist.$owner.id == userID else {
            throw Abort(.forbidden)
        }
        
        if let content = dto.content { item.content = content }
        if let isCompleted = dto.isCompleted { item.isCompleted = isCompleted }
        if let position = dto.position { item.position = position }
        
        try await item.save(on: req.db)
        
        return item
    }

    func deleteItem(req: Request) async throws -> Response {
        let userID = try req.auth.require(UserPayload.self).userID
        guard let itemID = req.parameters.get("itemID", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        guard let item = try await ChecklistItem.find(itemID, on: req.db) else {
            throw Abort(.notFound)
        }
        
        let checklist = try await item.$checklist.get(on: req.db)
        guard checklist.$owner.id == userID else {
            throw Abort(.forbidden)
        }
        
        try await item.delete(on: req.db)
        return Response(status: .ok)
    }
}
