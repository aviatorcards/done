import Vapor

enum ImportFormat: String, Content {
    case markdown
    case json
    case csv
}

struct ImportBoardDTO: Content {
    var format: ImportFormat
    var data: String
}
