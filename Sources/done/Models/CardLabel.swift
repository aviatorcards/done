import Fluent
import Vapor

final class CardLabel: Model, @unchecked Sendable {
    static let schema = "card_label"
    
    @ID(key: .id)
    var id: UUID?
    
    @Parent(key: "card_id")
    var card: Card
    
    @Parent(key: "label_id")
    var label: Label
    
    init() { }
    
    init(id: UUID? = nil, cardID: Card.IDValue, labelID: Label.IDValue) {
        self.id = id
        self.$card.id = cardID
        self.$label.id = labelID
    }
}
