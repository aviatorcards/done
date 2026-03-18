import Fluent
import Vapor

final class Label: Model, Content, @unchecked Sendable {
    static let schema = "labels"
    
    @ID(key: .id)
    var id: UUID?
    
    @Field(key: "name")
    var name: String
    
    @Field(key: "color_hex")
    var colorHex: String
    
    @Siblings(through: CardLabel.self, from: \.$label, to: \.$card)
    var cards: [Card]
    
    init() { }
    
    init(id: UUID? = nil, name: String, colorHex: String) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
    }
}
