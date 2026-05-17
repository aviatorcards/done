import Vapor
import Fluent

extension Request {
    func checkBoardAccess(boardID: UUID) async throws -> Board {
        let userID = try self.auth.require(UserPayload.self).userID
        guard let board = try await Board.find(boardID, on: self.db) else {
            throw Abort(.notFound)
        }
        
        let isOwner = board.$owner.id == userID
        let isMember = try await board.$members.query(on: self.db).filter(\User.$id == userID).first() != nil
        
        guard isOwner || isMember else {
            throw Abort(.forbidden)
        }
        
        return board
    }

    func checkColumnAccess(columnID: UUID) async throws -> (Column, Board) {
        let userID = try self.auth.require(UserPayload.self).userID
        guard let column = try await Column.query(on: self.db)
            .filter(\.$id == columnID)
            .with(\.$board)
            .first() else {
            throw Abort(.notFound)
        }
        
        let board = column.board
        let isOwner = board.$owner.id == userID
        let isMember = try await board.$members.query(on: self.db).filter(\User.$id == userID).first() != nil
        
        guard isOwner || isMember else {
            throw Abort(.forbidden)
        }
        
        return (column, board)
    }

    func checkCardAccess(cardID: UUID) async throws -> (Card, Column, Board) {
        let userID = try self.auth.require(UserPayload.self).userID
        
        let cardQuery = Card.query(on: self.db)
            .filter(\.$id == cardID)
            .with(\.$column) { column in
                column.with(\.$board)
            }
        
        guard let card = try await cardQuery.first() else {
            throw Abort(.notFound)
        }
        
        let column = card.column
        let board = column.board
        let isOwner = board.$owner.id == userID
        let isMember = try await board.$members.query(on: self.db).filter(\User.$id == userID).first() != nil
        
        guard isOwner || isMember else {
            throw Abort(.forbidden)
        }
        
        return (card, column, board)
    }
    
    func requireBoardOwner(board: Board) throws {
        let userID = try self.auth.require(UserPayload.self).userID
        guard board.$owner.id == userID else {
            throw Abort(.forbidden)
        }
    }
}
