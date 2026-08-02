import Vapor
import Fluent
import NIOCore
import NIOConcurrencyHelpers

/// Represents an appointment/repair job fetched from Cox Automotive / Xtime.
public struct CoxAppointment: Codable, Sendable {
    public let appointmentId: String
    public let repairOrderId: String?
    public let customerName: String
    public let customerPhone: String?
    public let customerEmail: String?
    public let vehicleYear: Int
    public let vehicleMake: String
    public let vehicleModel: String
    public let vehicleVin: String?
    public let vehicleMileage: Int?
    public let serviceAdvisor: String?
    public let requestedServices: [String]
    public let status: String // e.g. "scheduled", "checked_in", "in_progress", "quality_control", "completed"
    public let scheduledTime: Date
    public let promiseTime: Date?
    public let urgency: String // "low", "medium", "high"
    public let tag: String?
}

public struct CoxAutoTokenStorage: Sendable {
    public struct Token: Codable, Sendable {
        public let accessToken: String
        public let expiresAt: Date
        
        public var isValid: Bool {
            expiresAt > Date().addingTimeInterval(60) // 1-minute buffer
        }
    }
    public var token: Token?
}

extension Application {
    struct CoxAutoTokenKey: StorageKey {
        typealias Value = NIOLockedValueBox<CoxAutoTokenStorage>
    }
    
    public var coxAutoTokenBox: NIOLockedValueBox<CoxAutoTokenStorage> {
        if let box = self.storage[CoxAutoTokenKey.self] {
            return box
        } else {
            let box = NIOLockedValueBox(CoxAutoTokenStorage(token: nil))
            self.storage[CoxAutoTokenKey.self] = box
            return box
        }
    }
}

public struct CoxAutoService: Sendable {
    public let app: Application
    
    public init(app: Application) {
        self.app = app
    }
    
    /// True if we should run in offline mock mode (no real network requests).
    public var isMockMode: Bool {
        if let mockModeEnv = Environment.get("DMS_AUTO_MOCK_MODE") ?? Environment.get("COX_AUTO_MOCK_MODE") {
            return mockModeEnv.lowercased() == "true"
        }
        // If not explicitly set but credentials are empty, default to mock mode
        let clientID = Environment.get("DMS_API_CLIENT_ID") ?? Environment.get("COX_API_CLIENT_ID")
        let clientSecret = Environment.get("DMS_API_CLIENT_SECRET") ?? Environment.get("COX_API_CLIENT_SECRET")
        return clientID == nil || clientSecret == nil
    }
    
    /// Fetches a valid OAuth2 token or returns a cached one if still valid.
    private func getValidToken() async throws -> String {
        // Check cache
        if let cachedToken = app.coxAutoTokenBox.withLockedValue({ $0.token }), cachedToken.isValid {
            return cachedToken.accessToken
        }
        
        // Fetch new token
        let clientID = Environment.get("DMS_API_CLIENT_ID") ?? Environment.get("COX_API_CLIENT_ID")
        let clientSecret = Environment.get("DMS_API_CLIENT_SECRET") ?? Environment.get("COX_API_CLIENT_SECRET")
        guard let clientID = clientID,
              let clientSecret = clientSecret else {
            throw Abort(.internalServerError, reason: "DMS API client credentials not configured in environment.")
        }
        
        let tokenURL = URI(string: Environment.get("DMS_API_TOKEN_URL") ?? Environment.get("COX_API_TOKEN_URL") ?? "https://api.dms-scheduler-integration.local/oauth/token")
        let scope = Environment.get("DMS_API_SCOPE") ?? Environment.get("COX_API_SCOPE") ?? "dealer-ops.service.appointments.read"
        
        let credentials = "\(clientID):\(clientSecret)".data(using: .utf8)?.base64EncodedString() ?? ""
        
        let response = try await app.client.post(tokenURL) { req in
            req.headers.add(name: .contentType, value: "application/x-www-form-urlencoded")
            req.headers.add(name: .authorization, value: "Basic \(credentials)")
            try req.content.encode([
                "grant_type": "client_credentials",
                "scope": scope
            ], as: .urlEncodedForm)
        }
        
        struct OAuthResponse: Codable {
            let access_token: String
            let expires_in: Double
        }
        
        guard response.status == .ok else {
            app.logger.error("Failed to authenticate with DMS API: \(response.status)")
            throw Abort(.internalServerError, reason: "DMS API authentication failed.")
        }
        
        let oauthData = try response.content.decode(OAuthResponse.self)
        let expiresAt = Date().addingTimeInterval(oauthData.expires_in)
        let newToken = CoxAutoTokenStorage.Token(accessToken: oauthData.access_token, expiresAt: expiresAt)
        
        app.coxAutoTokenBox.withLockedValue { storage in
            storage.token = newToken
        }
        
        app.logger.info("Successfully fetched and cached new DMS API OAuth token.")
        return newToken.accessToken
    }
    
    /// Fetches service appointments from DMS API or returns mock ones.
    public func fetchAppointments() async throws -> [CoxAppointment] {
        if isMockMode {
            app.logger.info("DMS Integration: Fetching MOCK service appointments.")
            return generateMockAppointments()
        }
        
        let token = try await getValidToken()
        let apiURL = URI(string: Environment.get("DMS_API_BASE_URL") ?? Environment.get("COX_API_BASE_URL") ?? "https://api.dms-scheduler-integration.local/v1/appointments")
        
        let response = try await app.client.get(apiURL) { req in
            req.headers.add(name: .authorization, value: "Bearer \(token)")
            if let apiKey = Environment.get("DMS_API_KEY") ?? Environment.get("COX_API_KEY") {
                req.headers.add(name: "x-api-key", value: apiKey)
            }
        }
        
        guard response.status == .ok else {
            app.logger.error("Failed to fetch appointments from DMS API: \(response.status)")
            throw Abort(.internalServerError, reason: "Failed to retrieve appointments from DMS.")
        }
        
        return try response.content.decode([CoxAppointment].self)
    }
    
    /// Syncs appointments into the specified board.
    public func syncToBoard(boardID: UUID, db: any Database) async throws -> Int {
        guard let board = try await Board.find(boardID, on: db) else {
            throw Abort(.notFound, reason: "Board not found.")
        }
        
        // Create necessary columns if they don't exist
        try await ensureDefaultColumnsExist(boardID: boardID, db: db)
        
        let appointments = try await fetchAppointments()
        var updatedCount = 0
        
        for appt in appointments {
            // Find appropriate column for the status
            let column = try await resolveColumn(status: appt.status, on: boardID, db: db)
            let columnID = try column.requireID()
            
            // Build visual identifier for the card title
            let jobID = appt.repairOrderId ?? appt.appointmentId
            let tagStr = appt.tag.map { " | Tag \($0)" } ?? ""
            let prefix = appt.repairOrderId != nil ? "RO #\(jobID)\(tagStr)" : "Appt #\(jobID)\(tagStr)"
            let cardTitle = "[\(prefix)] \(appt.vehicleYear) \(appt.vehicleMake) \(appt.vehicleModel) - \(appt.customerName)"
            
            // Build rich markdown description for the card
            let servicesList = appt.requestedServices.map { "- \($0)" }.joined(separator: "\n")
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            let formattedScheduled = formatter.string(from: appt.scheduledTime)
            let formattedPromise = appt.promiseTime.map { formatter.string(from: $0) } ?? "N/A"
            
            let cardDescription = """
            ### 🚗 Vehicle & Customer Info
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
            
            // Try to find if this card already exists on the board (by matching the job prefix in brackets)
            let existingCard = try await Card.query(on: db)
                .join(Column.self, on: \Card.$column.$id == \Column.$id)
                .filter(Column.self, \Column.$board.$id == boardID)
                .filter(\Card.$title =~ "[\(prefix)]")
                .first()
                
            if let card = existingCard {
                // Update existing card details
                card.title = cardTitle
                card.description = cardDescription
                card.priority = appt.urgency
                card.dueDate = appt.promiseTime ?? appt.scheduledTime
                card.$column.id = columnID
                
                // Keep completed status sync'd
                let lowerStatus = appt.status.lowercased()
                card.isCompleted = (lowerStatus == "completed" || lowerStatus == "done" || lowerStatus == "finished")
                
                try await card.save(on: db)
                updatedCount += 1
            } else {
                // Determine next position in the target column
                let maxPos = try await Card.query(on: db)
                    .filter(\.$column.$id == columnID)
                    .max(\.$position) ?? -1
                    
                // Create new card
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
                try await newCard.save(on: db)
                updatedCount += 1
            }
        }
        
        // Broadcast websocket update for real-time reactivity
        app.webSocketManager.broadcast(boardID: boardID, message: "board_updated")
        
        return updatedCount
    }
    
    /// Ensures standard automotive/scheduling columns exist on the board.
    private func ensureDefaultColumnsExist(boardID: UUID, db: any Database) async throws {
        let existing = try await Column.query(on: db)
            .filter(\.$board.$id == boardID)
            .all()
            
        let titles = existing.map { $0.title.lowercased() }
        var nextPosition = existing.map { $0.position }.max() ?? -1
        nextPosition += 1
        
        let requiredColumns = [
            ("Scheduled", ["scheduled", "todo", "to do", "appointment"]),
            ("In Progress", ["in progress", "active", "work", "bay"]),
            ("Quality Control", ["quality", "qc", "review"]),
            ("Done", ["done", "completed", "finished", "pickup"])
        ]
        
        for (reqTitle, keywords) in requiredColumns {
            let exists = titles.contains { t in keywords.contains { t.contains($0) } }
            if !exists {
                let col = Column(title: reqTitle, position: nextPosition, boardID: boardID)
                try await col.save(on: db)
                nextPosition += 1
            }
        }
    }
    
    /// Finds the best matching column for a given Cox status.
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
        
        // Fallbacks
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
    
    /// Generates mock data representing realistic auto shop appointments.
    private func generateMockAppointments() -> [CoxAppointment] {
        let now = Date()
        
        return [
            CoxAppointment(
                appointmentId: "1001",
                repairOrderId: "20412",
                customerName: "John Miller",
                customerPhone: "(555) 019-2834",
                customerEmail: "john.miller@example.com",
                vehicleYear: 2020,
                vehicleMake: "Chevrolet",
                vehicleModel: "Silverado 1500",
                vehicleVin: "1GCUYDED2LZXXXXXX",
                vehicleMileage: 48500,
                serviceAdvisor: "Sarah Jenkins",
                requestedServices: ["Synthetic Oil & Filter Change", "Tire Rotation", "Multi-Point Inspection"],
                status: "scheduled",
                scheduledTime: now.addingTimeInterval(3600), // 1 hr from now
                promiseTime: now.addingTimeInterval(7200), // 2 hrs from now
                urgency: "low",
                tag: "949"
            ),
            CoxAppointment(
                appointmentId: "1002",
                repairOrderId: "20413",
                customerName: "David Brown",
                customerPhone: "(555) 014-9922",
                customerEmail: "dbrown88@example.com",
                vehicleYear: 2018,
                vehicleMake: "Ford",
                vehicleModel: "Explorer",
                vehicleVin: "1FM5K8F85JGXXXXXX",
                vehicleMileage: 74200,
                serviceAdvisor: "Sarah Jenkins",
                requestedServices: ["Diagnose Check Engine Light", "Replace Engine Air Filter", "Replace Spark Plugs"],
                status: "in_progress",
                scheduledTime: now.addingTimeInterval(-3600), // 1 hr ago
                promiseTime: now.addingTimeInterval(14400), // 4 hrs from now
                urgency: "medium",
                tag: "951"
            ),
            CoxAppointment(
                appointmentId: "1003",
                repairOrderId: "20414",
                customerName: "Maria Garcia",
                customerPhone: "(555) 017-8811",
                customerEmail: "m.garcia@example.com",
                vehicleYear: 2021,
                vehicleMake: "Toyota",
                vehicleModel: "RAV4",
                vehicleVin: "JTMDFRFV6MDXXXXXX",
                vehicleMileage: 31200,
                serviceAdvisor: "Mike Davis",
                requestedServices: ["Front Brake Pad & Rotor Replacement", "Brake Fluid Flush"],
                status: "in_progress",
                scheduledTime: now.addingTimeInterval(-7200), // 2 hrs ago
                promiseTime: now.addingTimeInterval(3600), // 1 hr from now
                urgency: "high",
                tag: "954"
            ),
            CoxAppointment(
                appointmentId: "1004",
                repairOrderId: "20415",
                customerName: "Robert Johnson",
                customerPhone: "(555) 012-3456",
                customerEmail: "rjohnson@example.com",
                vehicleYear: 2017,
                vehicleMake: "Honda",
                vehicleModel: "Civic",
                vehicleVin: "1HGFC2F85HHXXXXXX",
                vehicleMileage: 89000,
                serviceAdvisor: "Mike Davis",
                requestedServices: ["A/C System Recharge & Leak Test", "Cabin Air Filter Replacement"],
                status: "in_progress",
                scheduledTime: now.addingTimeInterval(-10800), // 3 hrs ago
                promiseTime: now.addingTimeInterval(18000), // 5 hrs from now
                urgency: "medium",
                tag: "966"
            ),
            CoxAppointment(
                appointmentId: "1005",
                repairOrderId: "20416",
                customerName: "Emily Davis",
                customerPhone: "(555) 013-4567",
                customerEmail: "emily.d@example.com",
                vehicleYear: 2022,
                vehicleMake: "Tesla",
                vehicleModel: "Model Y",
                vehicleVin: "5YJYGDEF2NFXXXXXX",
                vehicleMileage: 19500,
                serviceAdvisor: "Sarah Jenkins",
                requestedServices: ["Replace Wiper Blades", "Windshield Washer Fluid Refill"],
                status: "quality_control",
                scheduledTime: now.addingTimeInterval(-14400), // 4 hrs ago
                promiseTime: now.addingTimeInterval(-1800), // 30 mins ago
                urgency: "low",
                tag: "998"
            ),
            CoxAppointment(
                appointmentId: "1006",
                repairOrderId: "20417",
                customerName: "James Wilson",
                customerPhone: "(555) 018-7654",
                customerEmail: "jwilson@example.com",
                vehicleYear: 2019,
                vehicleMake: "Jeep",
                vehicleModel: "Grand Cherokee",
                vehicleVin: "1C4RJFAG4KCXXXXXX",
                vehicleMileage: 62000,
                serviceAdvisor: "Mike Davis",
                requestedServices: ["Transmission Fluid Service / Flush", "Rear Differential Fluid Service"],
                status: "completed",
                scheduledTime: now.addingTimeInterval(-21600), // 6 hrs ago
                promiseTime: now.addingTimeInterval(-7200), // 2 hrs ago
                urgency: "medium",
                tag: "990"
            )
        ]
    }
}

extension Application {
    public var coxAutoService: CoxAutoService {
        .init(app: self)
    }
}

extension Request {
    public var coxAutoService: CoxAutoService {
        .init(app: self.application)
    }
}
