import Fluent
import Vapor

struct MarkdownKanbanColumn {
    let title: String
    var cards: [MarkdownKanbanCard]
}

struct MarkdownKanbanCard {
    let title: String
    var description: String
    var isCompleted: Bool
    var priority: String
}

final class KanbanImportService: Sendable {
    func parseMarkdown(markdown: String) -> (title: String, columns: [MarkdownKanbanColumn]) {
        let lines = markdown.components(separatedBy: .newlines)
        var columns: [MarkdownKanbanColumn] = []
        var currentColumn: MarkdownKanbanColumn?
        var currentCard: MarkdownKanbanCard?

        var boardTitle = "Imported Board"

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            // Check for Column Header (## Title)
            if trimmed.hasPrefix("## ") {
                // Save previous card and column
                if let card = currentCard, var column = currentColumn {
                    column.cards.append(card)
                    currentCard = nil
                    currentColumn = column
                }

                if let column = currentColumn {
                    columns.append(column)
                }

                let title = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                currentColumn = MarkdownKanbanColumn(title: title, cards: [])
                continue
            }

            // Check for Card (- [ ] Title or - [x] Title)
            if trimmed.hasPrefix("- [ ] ") || trimmed.hasPrefix("- [x] ") {
                // Save previous card
                if let card = currentCard {
                    currentColumn?.cards.append(card)
                }

                let isCompleted = trimmed.hasPrefix("- [x] ")
                let content = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                currentCard = MarkdownKanbanCard(
                    title: content, description: "", isCompleted: isCompleted, priority: "Medium")
                continue
            }

            // Handle sub-items or description (starts with tab or space indentation)
            if (line.hasPrefix("\t") || line.hasPrefix("    ") || line.hasPrefix(" "))
                && currentCard != nil
            {
                let content = line.trimmingCharacters(in: .whitespaces)
                if !content.isEmpty {
                    if currentCard?.description.isEmpty == true {
                        currentCard?.description = content
                    } else {
                        currentCard?.description += "\n" + content
                    }
                }
                continue
            }

            // Collect metadata if any
            if trimmed.hasPrefix("# ") && boardTitle == "Imported Board" {
                boardTitle = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            }
        }

        // Finalize
        if let card = currentCard {
            currentColumn?.cards.append(card)
        }
        if let column = currentColumn {
            columns.append(column)
        }

        return (boardTitle, columns)
    }

    func importToDatabase(req: Request, dto: ImportBoardDTO, ownerID: UUID) async throws -> Board {
        switch dto.format {
        case .markdown:
            return try await importMarkdown(req: req, markdown: dto.data, ownerID: ownerID)
        case .json:
            return try await importJSON(req: req, jsonData: dto.data, ownerID: ownerID)
        case .csv:
            return try await importCSV(req: req, csvData: dto.data, ownerID: ownerID)
        }
    }

    func importMarkdown(req: Request, markdown: String, ownerID: UUID) async throws -> Board {
        let (title, parsedColumns) = parseMarkdown(markdown: markdown)
        return try await createBoard(
            req: req, title: title, columns: parsedColumns, ownerID: ownerID)
    }

    func importJSON(req: Request, jsonData: String, ownerID: UUID) async throws -> Board {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = Data(jsonData.utf8)

        let boardsToImport: [BoardExportDTO]

        // Try decoding as a full account export first
        if let fullExport = try? decoder.decode(UserDataExportDTO.self, from: data) {
            boardsToImport = fullExport.ownedBoards
        } else {
            // Fall back to a single board export
            let singleBoard = try decoder.decode(BoardExportDTO.self, from: data)
            boardsToImport = [singleBoard]
        }

        guard !boardsToImport.isEmpty else {
            throw Abort(.badRequest, reason: "No boards found in JSON")
        }

        var lastCreatedBoard: Board?

        for boardDTO in boardsToImport {
            let board = Board(title: boardDTO.title, ownerID: ownerID)
            try await board.save(on: req.db)
            let boardID = try board.requireID()

            for colDTO in boardDTO.columns {
                let column = Column(
                    title: colDTO.title, position: colDTO.position, boardID: boardID)
                try await column.save(on: req.db)
                let columnID = try column.requireID()

                for cardDTO in colDTO.cards {
                    let card = Card(
                        title: cardDTO.title,
                        description: cardDTO.description,
                        position: cardDTO.position,
                        dueDate: cardDTO.dueDate,
                        priority: cardDTO.priority,
                        isCompleted: cardDTO.isCompleted,
                        columnID: columnID
                    )
                    try await card.save(on: req.db)

                    // Note: Comments and labels could be imported here if we want to be thorough
                    // For now, staying consistent with the previous logic
                }
            }
            lastCreatedBoard = board
        }

        return lastCreatedBoard!
    }

    func importCSV(req: Request, csvData: String, ownerID: UUID) async throws -> Board {
        let lines = csvData.components(separatedBy: .newlines).filter {
            !$0.trimmingCharacters(in: .whitespaces).isEmpty
        }
        guard !lines.isEmpty else { throw Abort(.badRequest, reason: "Empty CSV") }

        // Simple CSV parser (doesn't handle quoted newlines, but good enough for this)
        func parseCSVLine(_ line: String) -> [String] {
            var result: [String] = []
            var current = ""
            var inQuotes = false

            for char in line {
                if char == "\"" {
                    inQuotes.toggle()
                } else if char == "," && !inQuotes {
                    result.append(
                        current.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(
                            in: CharacterSet(charactersIn: "\"")))
                    current = ""
                } else {
                    current.append(char)
                }
            }
            result.append(
                current.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(
                    in: CharacterSet(charactersIn: "\"")))
            return result
        }

        let header = parseCSVLine(lines[0]).map { $0.lowercased() }
        let titleIdx = header.firstIndex(of: "title") ?? 0
        let descIdx = header.firstIndex(of: "description")
        let colIdx = header.firstIndex(of: "column")
        let prioIdx = header.firstIndex(of: "priority")
        let compIdx = header.firstIndex(of: "completed")

        var columnsMap: [String: [MarkdownKanbanCard]] = [:]
        var columnOrder: [String] = []

        for i in 1..<lines.count {
            let fields = parseCSVLine(lines[i])
            guard fields.count > titleIdx else { continue }

            let title = fields[titleIdx]
            let description = descIdx != nil && fields.count > descIdx! ? fields[descIdx!] : ""
            let colName = colIdx != nil && fields.count > colIdx! ? fields[colIdx!] : "To Do"
            let priority = prioIdx != nil && fields.count > prioIdx! ? fields[prioIdx!] : "Medium"
            let isCompleted =
                compIdx != nil && fields.count > compIdx!
                ? (fields[compIdx!].lowercased() == "true" || fields[compIdx!] == "1") : false
            let card = MarkdownKanbanCard(
                title: title, description: description, isCompleted: isCompleted, priority: priority
            )
            // Note: We're using MarkdownKanbanCard for convenience even though it lacks priority,
            // maybe better to define a more robust intermediate type.
            // Let's stick with a custom logic for CSV to support priority.

            if columnsMap[colName] == nil {
                columnsMap[colName] = []
                columnOrder.append(colName)
            }
            columnsMap[colName]?.append(card)
        }

        let board = Board(title: "Imported CSV Board", ownerID: ownerID)
        try await board.save(on: req.db)
        let boardID = try board.requireID()

        for (index, colName) in columnOrder.enumerated() {
            let column = Column(title: colName, position: index, boardID: boardID)
            try await column.save(on: req.db)
            let columnID = try column.requireID()

            for (cardIndex, cardData) in (columnsMap[colName] ?? []).enumerated() {
                // Find priority from fields if we were to store it in cardData
                // For now, let's just use "Medium" or try to find it again from fields
                // Actually, I should have stored it in cardData or a custom struct.
                // Let's just fix the immediate warning by using the variable if I can,
                // but since cardData is MarkdownKanbanCard, it doesn't have priority.
                // I'll update the loop to have access to fields again or use a better struct.

                let card = Card(
                    title: cardData.title,
                    description: cardData.description,
                    position: cardIndex,
                    priority: cardData.priority,
                    isCompleted: cardData.isCompleted,
                    columnID: columnID
                )
                try await card.save(on: req.db)
            }
        }

        return board
    }

    private func createBoard(
        req: Request, title: String, columns: [MarkdownKanbanColumn], ownerID: UUID
    ) async throws -> Board {
        let board = Board(title: title, ownerID: ownerID)
        try await board.save(on: req.db)

        let boardID = try board.requireID()

        for (index, col) in columns.enumerated() {
            let column = Column(title: col.title, position: index, boardID: boardID)
            try await column.save(on: req.db)

            let columnID = try column.requireID()

            for (cardIndex, cardData) in col.cards.enumerated() {
                let card = Card(
                    title: cardData.title,
                    description: cardData.description,
                    position: cardIndex,
                    dueDate: nil,
                    priority: "Medium",
                    isCompleted: cardData.isCompleted,
                    columnID: columnID
                )
                try await card.save(on: req.db)
            }
        }

        return board
    }
}
