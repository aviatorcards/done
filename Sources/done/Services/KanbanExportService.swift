import Vapor
import Fluent

final class KanbanExportService: Sendable {
    func exportBoard(_ board: Board, on db: any Database, format: ImportFormat) async throws -> Response {
        let boardDTO = try await gatherBoardData(for: board, on: db)
        
        switch format {
        case .json:
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let jsonData = try encoder.encode(boardDTO)
            let response = Response(status: .ok)
            response.body = .init(data: jsonData)
            response.headers.contentType = .json
            response.headers.replaceOrAdd(name: .contentDisposition, value: "attachment; filename=\"\(board.title.safeFilename()).json\"")
            return response
            
        case .markdown:
            let markdown = convertToMarkdown(boardDTO)
            let response = Response(status: .ok)
            response.body = .init(string: markdown)
            response.headers.contentType = .init(type: "text", subType: "markdown")
            response.headers.replaceOrAdd(name: .contentDisposition, value: "attachment; filename=\"\(board.title.safeFilename()).md\"")
            return response
            
        case .csv:
            let csv = convertToCSV(boardDTO)
            let response = Response(status: .ok)
            response.body = .init(string: csv)
            response.headers.contentType = .init(type: "text", subType: "csv")
            response.headers.replaceOrAdd(name: .contentDisposition, value: "attachment; filename=\"\(board.title.safeFilename()).csv\"")
            return response
        }
    }
    
    func gatherBoardData(for board: Board, on db: any Database) async throws -> BoardExportDTO {
        let columns = try await Column.query(on: db)
            .filter(\.$board.$id == board.requireID())
            .with(\.$cards) { card in
                card.with(\.$labels)
                card.with(\.$comments) { comment in
                    comment.with(\.$user)
                }
                card.with(\.$assignee)
            }
            .sort(\.$position, .ascending)
            .all()
        
        let columnDTOs = columns.map { column in
            ColumnExportDTO(
                title: column.title,
                position: column.position,
                cards: column.cards.map { card in
                    CardExportDTO(
                        title: card.title,
                        description: card.description,
                        position: card.position,
                        priority: card.priority,
                        dueDate: card.dueDate,
                        isCompleted: card.isCompleted,
                        comments: card.comments.map { comment in
                            CommentExportDTO(
                                content: comment.text,
                                author: comment.user.username,
                                createdAt: comment.createdAt
                            )
                        },
                        labels: card.labels.map { $0.name },
                        assignee: card.assignee?.username
                    )
                }
            )
        }
        
        try await board.$owner.load(on: db)
        return BoardExportDTO(
            title: board.title,
            columns: columnDTOs,
            owner: board.owner.username
        )
    }
    
    private func convertToMarkdown(_ dto: BoardExportDTO) -> String {
        var markdown = "# \(dto.title)\n\n"
        markdown += "---\nkanban-plugin: board\n---\n\n"
        
        for column in dto.columns {
            markdown += "## \(column.title)\n"
            for card in column.cards {
                let status = card.isCompleted ? "x" : " "
                markdown += "- [\(status)] \(card.title)\n"
                if !card.description.isEmpty {
                    let indented = card.description.components(separatedBy: .newlines).map { "    \($0)" }.joined(separator: "\n")
                    markdown += "\(indented)\n"
                }
            }
            markdown += "\n"
        }
        return markdown
    }
    
    private func convertToCSV(_ dto: BoardExportDTO) -> String {
        var csv = "Title,Description,Column,Priority,Completed\n"
        for column in dto.columns {
            for card in column.cards {
                let title = quoteCSV(card.title)
                let desc = quoteCSV(card.description)
                let col = quoteCSV(column.title)
                let prio = quoteCSV(card.priority)
                let comp = card.isCompleted ? "true" : "false"
                csv += "\(title),\(desc),\(col),\(prio),\(comp)\n"
            }
        }
        return csv
    }
    
    private func quoteCSV(_ string: String) -> String {
        if string.contains(",") || string.contains("\"") || string.contains("\n") {
            let escaped = string.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return string
    }
}

extension String {
    func safeFilename() -> String {
        return self.map { char in
            if "\\/:*?\"<>|".contains(char) {
                return Character("_")
            } else {
                return char
            }
        }.map { String($0) }.joined()
    }
}
