import Vapor
import Fluent

struct CoxAutoController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let authenticated = routes.grouped(AuthMiddleware())
        
        // Manual Sync Route
        authenticated.post("api", "integrations", "dms", "sync", ":boardID", use: syncAppointments)
        
        // Public Webhook Route (for DMS system-to-system notifications)
        routes.post("api", "integrations", "dms", "webhook", use: receiveWebhook)
    }
    
    /// Triggered manually by the user clicking a "Sync" button in the interface.
    func syncAppointments(req: Request) async throws -> Response {
        guard let boardID = req.parameters.get("boardID", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid board ID.")
        }
        
        // Verify user has access to this board
        _ = try await req.checkBoardAccess(boardID: boardID)
        
        req.logger.info("Triggering DMS Sync for Board: \(boardID)")
        
        let syncCount = try await req.coxAutoService.syncToBoard(boardID: boardID, db: req.db)
        
        req.logger.info("Synced \(syncCount) appointments/repair orders successfully.")
        
        // Support HTMX responses (page reload signals)
        if req.headers.contains(name: "HX-Request") {
            let response = Response(status: .ok)
            response.headers.add(name: "HX-Refresh", value: "true")
            return response
        }
        
        // Fallback to standard redirect
        return req.redirect(to: "/boards/\(boardID)")
    }
    
    /// Webhook payload structure from Cox Automotive event subscriptions.
    struct CoxWebhookPayload: Content {
        let event: String // e.g. "appointment_created", "status_changed"
        let boardID: UUID
        let appointment: CoxAppointment
    }
    
    /// Public webhook endpoint for real-time DMS event updates.
    func receiveWebhook(req: Request) async throws -> Response {
        // Optional webhook signature verification
        if let secret = Environment.get("DMS_WEBHOOK_SECRET") ?? Environment.get("COX_WEBHOOK_SECRET") {
            let signature = req.headers.first(name: "X-DMS-Signature") ?? req.headers.first(name: "X-Cox-Signature")
            guard signature == secret else {
                req.logger.warning("Unauthorized webhook payload received (bad signature).")
                throw Abort(.unauthorized, reason: "Invalid webhook signature.")
            }
        }
        
        let payload = try req.content.decode(CoxWebhookPayload.self)
        req.logger.info("Received DMS webhook event '\(payload.event)' for board: \(payload.boardID)")
        
        let boardID = payload.boardID
        guard let board = try await Board.find(boardID, on: req.db) else {
            req.logger.error("Webhook target board \(boardID) not found.")
            throw Abort(.notFound, reason: "Target board not found.")
        }
        
        let appt = payload.appointment
        
        // Resolve target column
        let columns = try await Column.query(on: req.db)
            .filter(\.$board.$id == boardID)
            .all()
            
        // Map status to a column
        let column = try await resolveColumn(status: appt.status, on: boardID, db: req.db)
        let columnID = try column.requireID()
        
        let jobID = appt.repairOrderId ?? appt.appointmentId
        let prefix = appt.repairOrderId != nil ? "RO #\(jobID)" : "Appt #\(jobID)"
        let cardTitle = "[\(prefix)] \(appt.vehicleYear) \(appt.vehicleMake) \(appt.vehicleModel) - \(appt.customerName)"
        
        let servicesList = appt.requestedServices.map { "- \($0)" }.joined(separator: "\n")
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let formattedScheduled = formatter.string(from: appt.scheduledTime)
        let formattedPromise = appt.promiseTime.map { formatter.string(from: $0) } ?? "N/A"
        
        let cardDescription = """
        ### 🚗 Vehicle & Customer Info (Real-Time Sync)
        - **Customer**: \(appt.customerName)
        - **Phone**: \(appt.customerPhone ?? "N/A")
        - **Email**: \(appt.customerEmail ?? "N/A")
        - **VIN**: `\(appt.vehicleVin ?? "N/A")`
        - **Mileage**: \(appt.vehicleMileage.map { "\($0) miles" } ?? "N/A")
        
        ### 📅 Schedule
        - **Check-in**: \(formattedScheduled)
        - **Promise Time**: \(formattedPromise)
        - **Service Advisor**: \(appt.serviceAdvisor ?? "N/A")
        
        ### 🔧 Requested Services
        \(servicesList)
        """
        
        let existingCard = try await Card.query(on: req.db)
            .join(Column.self, on: \Card.$column.$id == \Column.$id)
            .filter(Column.self, \Column.$board.$id == boardID)
            .filter(\Card.$title =~ "[\(prefix)]")
            .first()
            
        if let card = existingCard {
            card.title = cardTitle
            card.description = cardDescription
            card.priority = appt.urgency
            card.dueDate = appt.promiseTime ?? appt.scheduledTime
            card.$column.id = columnID
            
            let lowerStatus = appt.status.lowercased()
            card.isCompleted = (lowerStatus == "completed" || lowerStatus == "done" || lowerStatus == "finished")
            
            try await card.save(on: req.db)
            req.logger.info("Updated card for RO/Appt: \(jobID)")
        } else {
            let maxPos = try await Card.query(on: req.db)
                .filter(\.$column.$id == columnID)
                .max(\.$position) ?? -1
                
            let lowerStatus = appt.status.lowercased()
            let isCompleted = (lowerStatus == "completed" || lowerStatus == "done" || lowerStatus == "finished")
            
            let newCard = Card(
                title: cardTitle,
                description: cardDescription,
                position: maxPos + 1,
                dueDate: appt.promiseTime ?? appt.scheduledTime,
                priority: appt.urgency,
                isCompleted: isCompleted,
                columnID: columnID
            )
            try await newCard.save(on: req.db)
            req.logger.info("Created new card for RO/Appt: \(jobID)")
        }
        
        // Broadcast updates to active board connections
        req.application.webSocketManager.broadcast(boardID: boardID, message: "board_updated")
        
        return Response(status: .ok)
    }
    
    private func resolveColumn(status: String, on boardID: UUID, db: any Database) async throws -> Column {
        let columns = try await Column.query(on: db)
            .filter(\.$board.$id == boardID)
            .sort(\.$position, .ascending)
            .all()
            
        let normalized = status.lowercased()
        
        func findColumn(matching keywords: [String]) -> Column? {
            columns.first { col in
                keywords.contains { kw in col.title.lowercased().contains(kw) }
            }
        }
        
        if normalized == "scheduled" || normalized == "appointment" {
            if let col = findColumn(matching: ["scheduled", "appointment", "todo", "to do"]) { return col }
        } else if normalized == "checked_in" {
            if let col = findColumn(matching: ["checked in", "check-in", "todo", "to do", "progress", "bay"]) { return col }
        } else if normalized == "in_progress" || normalized == "active" {
            if let col = findColumn(matching: ["progress", "active", "work", "bay"]) { return col }
        } else if normalized == "quality_control" {
            if let col = findColumn(matching: ["quality", "qc", "review", "checking", "progress"]) { return col }
        } else if normalized == "completed" || normalized == "done" {
            if let col = findColumn(matching: ["done", "completed", "finished", "pickup"]) { return col }
        }
        
        if columns.isEmpty {
            let defaultCol = Column(title: "Scheduled", position: 0, boardID: boardID)
            try await defaultCol.save(on: db)
            return defaultCol
        }
        
        if normalized == "scheduled" || normalized == "appointment" {
            return columns.first!
        } else if normalized == "completed" || normalized == "done" {
            return columns.last!
        } else {
            if columns.count > 1 {
                return columns[columns.count / 2]
            }
            return columns.first!
        }
    }
}
