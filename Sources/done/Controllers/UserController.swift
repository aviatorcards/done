import Vapor
import Fluent

struct UserController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let users = routes.grouped(AuthMiddleware())
            .grouped("users")
        
        users.patch("profile", use: updateProfile)
        users.post("avatar", use: uploadAvatar)
        users.post("invite", use: inviteToSite)
        users.get("export", use: exportData)
        users.post("delete", use: deleteAccount)
    }

    struct SiteInviteDTO: Content {
        var email: String
    }

    func inviteToSite(req: Request) async throws -> Response {
        let payload = try req.auth.require(UserPayload.self)
        guard let inviter = try await User.find(payload.userID, on: req.db) else {
            throw Abort(.notFound)
        }

        let dto = try req.content.decode(SiteInviteDTO.self)
        let code = String((0..<8).map { _ in "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789".randomElement()! })
        
        let invite = InviteCode(
            code: code,
            email: dto.email,
            boardID: nil,
            inviterID: try inviter.requireID()
        )
        try await invite.save(on: req.db)
        
        try await req.application.emailService.sendInvite(
            to: dto.email,
            code: code,
            boardTitle: nil,
            inviterName: inviter.username
        )
        
        return Response(status: .ok)
    }

    func updateProfile(req: Request) async throws -> UserDTO.Public {
        let updateData = try req.content.decode(UserDTO.self)
        let payload = try req.auth.require(UserPayload.self)
        
        guard let user = try await User.find(payload.userID, on: req.db) else {
            throw Abort(.notFound)
        }

        if let newPassword = updateData.newPassword {
            guard let currentPassword = updateData.currentPassword else {
                throw Abort(.badRequest, reason: "Current password required to set a new one")
            }
            
            guard try Bcrypt.verify(currentPassword, created: user.passwordHash) else {
                throw Abort(.unauthorized, reason: "Incorrect current password")
            }
            
            user.passwordHash = try Bcrypt.hash(newPassword)
        }

        try await user.save(on: req.db)
        return user.toPublic()
    }

    func uploadAvatar(req: Request) async throws -> UserDTO.Public {
        let payload = try req.auth.require(UserPayload.self)
        guard let user = try await User.find(payload.userID, on: req.db) else {
            throw Abort(.notFound)
        }

        struct UploadData: Content {
            var avatar: File
        }
        let data = try req.content.decode(UploadData.self)

        let filename = "\(payload.userID.uuidString)-\(Int(Date().timeIntervalSince1970)).\(data.avatar.extension ?? "jpg")"
        let path = req.application.directory.publicDirectory + "uploads/avatars/" + filename
        
        // Ensure directory exists
        try await req.fileio.writeFile(data.avatar.data, at: path)
        
        user.avatarUrl = "/uploads/avatars/" + filename
        try await user.save(on: req.db)
        
        return user.toPublic()
    }

    func exportData(req: Request) async throws -> Response {
        let payload = try req.auth.require(UserPayload.self)
        let user = try await User.query(on: req.db)
            .filter(\.$id == payload.userID)
            .with(\.$sharedBoards) { board in
                board.with(\.$owner)
            }
            .with(\.$boards) { board in
                board.with(\.$owner)
            }
            .first()
            
        guard let user = user else {
            throw Abort(.notFound)
        }

        let ownedBoardDTOs = try await gatherBoardData(for: user.boards, on: req.db)
        let sharedBoardDTOs = try await gatherBoardData(for: user.sharedBoards, on: req.db)
        
        let invites = try await InviteCode.query(on: req.db)
            .filter(\.$inviter.$id == payload.userID)
            .with(\.$board)
            .all()
            
        let inviteDTOs = invites.map { invite in
            InviteExportDTO(
                code: invite.code,
                email: invite.email,
                boardTitle: invite.board?.title,
                createdAt: invite.createdAt
            )
        }

        let exportDTO = UserDataExportDTO(
            profile: user.toPublic(),
            ownedBoards: ownedBoardDTOs,
            sharedBoards: sharedBoardDTOs,
            createdInvites: inviteDTOs
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let jsonData = try encoder.encode(exportDTO)
        
        let response = Response(status: .ok)
        response.body = .init(data: jsonData)
        response.headers.contentType = .json
        response.headers.replaceOrAdd(name: .contentDisposition, value: "attachment; filename=done_data_export.json")
        return response
    }

    private func gatherBoardData(for boards: [Board], on db: any Database) async throws -> [BoardExportDTO] {
        var boardDTOs: [BoardExportDTO] = []
        for board in boards {
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
            
            boardDTOs.append(BoardExportDTO(
                title: board.title,
                columns: columnDTOs,
                owner: board.owner.username
            ))
        }
        return boardDTOs
    }

    func deleteAccount(req: Request) async throws -> Response {
        let payload = try req.auth.require(UserPayload.self)
        guard let user = try await User.find(payload.userID, on: req.db) else {
            throw Abort(.notFound)
        }

        // 1. Delete all owned boards (uses logic from BoardController)
        let boards = try await user.$boards.get(on: req.db)
        for board in boards {
            try await deleteBoardRecursively(board, on: req.db, req: req)
        }

        // 2. Clear assignments on ANY cards (where the user was assigned)
        let cardsWithUser = try await Card.query(on: req.db)
            .filter(\.$assignee.$id == payload.userID)
            .all()
        for card in cardsWithUser {
            card.$assignee.id = nil
            try await card.save(on: req.db)
        }

        // 3. Delete comments made by user on OTHERS' boards (owned boards' comments are already gone)
        try await Comment.query(on: req.db)
            .filter(\.$user.$id == payload.userID)
            .delete()

        // 4. Delete user itself (will cascade to board_members and invite_codes)
        try await user.delete(on: req.db)

        // Clear session/cookies
        let response = Response(status: .ok)
        response.cookies["token"] = .init(stringLiteral: "")
        return response
    }

    private func deleteBoardRecursively(_ board: Board, on db: any Database, req: Request) async throws {
        let boardID = try board.requireID()
        
        let columns = try await Column.query(on: db)
            .filter(\.$board.$id == boardID)
            .all()
        
        let columnIDs = try columns.map { try $0.requireID() }
        
        if !columnIDs.isEmpty {
            let cards = try await Card.query(on: db)
                .filter(\.$column.$id ~~ columnIDs)
                .all()
            
            let cardIDs = try cards.map { try $0.requireID() }
            
            if !cardIDs.isEmpty {
                try await CardLabel.query(on: db)
                    .filter(\.$card.$id ~~ cardIDs)
                    .delete()
                    
                try await Comment.query(on: db)
                    .filter(\.$card.$id ~~ cardIDs)
                    .delete()
                    
                try await Card.query(on: db)
                    .filter(\.$column.$id ~~ columnIDs)
                    .delete()
            }
            
            try await Column.query(on: db)
                .filter(\.$board.$id == boardID)
                .delete()
        }
        
        // Delete members
        try await BoardMember.query(on: db)
            .filter(\.$board.$id == boardID)
            .delete()

        // Delete board invites
        try await InviteCode.query(on: db)
            .filter(\.$board.$id == boardID)
            .delete()

        // Notify via WebSocket
        req.application.webSocketManager.broadcast(boardID: boardID, message: "board_deleted")
            
        try await board.delete(on: db)
    }
}
