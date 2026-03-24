import Vapor

struct UserDataExportDTO: Content {
    var profile: UserDTO.Public
    var ownedBoards: [BoardExportDTO]
    var sharedBoards: [BoardExportDTO]
    var createdInvites: [InviteExportDTO]
}

struct BoardExportDTO: Content {
    var title: String
    var columns: [ColumnExportDTO]
    var owner: String
}

struct ColumnExportDTO: Content {
    var title: String
    var position: Int
    var cards: [CardExportDTO]
}

struct CardExportDTO: Content {
    var title: String
    var description: String
    var position: Int
    var priority: String
    var dueDate: Date?
    var isCompleted: Bool
    var comments: [CommentExportDTO]
    var labels: [String]
    var assignee: String?
}

struct CommentExportDTO: Content {
    var content: String
    var author: String
    var createdAt: Date?
}

struct InviteExportDTO: Content {
    var code: String
    var email: String
    var boardTitle: String?
    var createdAt: Date?
}
