import Vapor

struct AnySendable: Sendable, Content {
    let value: any Sendable & Content
    
    init(_ value: any Sendable & Content) {
        self.value = value
    }
    
    func encode(to encoder: any Encoder) throws {
        try value.encode(to: encoder)
    }
    
    init(from decoder: any Decoder) throws {
        fatalError("Not implemented")
    }
}
