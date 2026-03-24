import Vapor
import Fluent

struct MarkdownKanbanColumn {
    let title: String
    var cards: [MarkdownKanbanCard]
}

struct MarkdownKanbanCard {
    let title: String
    var description: String
    var isCompleted: Bool
}

final class KanbanImportService: Sendable {
    func parse(markdown: String) -> (title: String, columns: [MarkdownKanbanColumn]) {
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
            if (trimmed.hasPrefix("- [ ] ") || trimmed.hasPrefix("- [x] ")) {
                // Save previous card
                if let card = currentCard {
                    currentColumn?.cards.append(card)
                }
                
                let isCompleted = trimmed.hasPrefix("- [x] ")
                let content = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                currentCard = MarkdownKanbanCard(title: content, description: "", isCompleted: isCompleted)
                continue
            }
            
            // Handle sub-items or description (starts with tab or space indentation)
            if (line.hasPrefix("\t") || line.hasPrefix("    ") || line.hasPrefix(" ")) && currentCard != nil {
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
    
    func importToDatabase(req: Request, markdown: String, ownerID: UUID) async throws -> Board {
        let (title, parsedColumns) = parse(markdown: markdown)
        
        let board = Board(title: title, ownerID: ownerID)
        try await board.save(on: req.db)
        
        let boardID = try board.requireID()
        
        for (index, col) in parsedColumns.enumerated() {
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
