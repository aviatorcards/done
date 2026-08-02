# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Project Is

**Done.** is a Kanban board web app (Trello-style) for small teams and personal projects. Built with Swift 6 / Vapor 4 on the backend, server-rendered Leaf templates, and HTMX + Alpine.js + Tailwind CSS on the frontend. Real-time collaboration happens via Vapor WebSockets.

## Commands

```bash
# Build
swift build

# Run locally (SQLite, http://127.0.0.1:8080)
swift run

# Run all tests
swift test

# Run a single test
swift test --filter AccessControlTests/testUnauthorizedCardCreation

# Docker (Postgres)
docker compose up --build        # build and start app + DB
docker compose run migrate       # run migrations (first time)
docker compose down -v           # wipe DB volume
```

Tests run against an in-memory SQLite database with auto-migrate + auto-revert per test case.

## Architecture

### Database Strategy
- **Local development**: SQLite file (`done.sqlite`) — used automatically when `DATABASE_HOST` env var is absent
- **Docker/production**: PostgreSQL — activated when `DATABASE_HOST` is set
- Schema is managed via Fluent migrations in `Sources/done/Migrations/`. Migrations run automatically on startup via `app.autoMigrate()` in `configure.swift`.

### Authentication
JWT tokens are stored in an `httpOnly` cookie named `token`. `AuthMiddleware` extracts the token from either the `Authorization: Bearer` header or the cookie, verifies it, and populates `request.auth` with a `UserPayload`.

For browser requests (non-HTMX), expired/missing tokens redirect to `/`. For HTMX/API requests, they return `401`.

### Access Control Pattern
All board/column/card access checks go through extension methods on `Request` defined in `Sources/done/Utilities/AuthHelpers.swift`:
- `req.checkBoardAccess(boardID:)` — verifies the authenticated user is the board owner or a member
- `req.checkColumnAccess(columnID:)` — loads the column's parent board and checks the same
- `req.checkCardAccess(cardID:)` — loads card → column → board chain and checks
- `req.requireBoardOwner(board:)` — throws `.forbidden` if the user is not the board owner (used for destructive/admin actions)

### Real-Time Updates
`WebSocketManager` (a Vapor `Application` storage extension) maintains a `[boardID: [connectionID: WebSocket]]` map. After any mutation (card moved, column renamed, board deleted, etc.), controllers call `req.application.webSocketManager.broadcast(boardID:, message:)`. The frontend reconnects and re-fetches board state on receipt.

WebSocket connections are established at `GET /board/:boardID/live` and require a valid JWT (checked by `AuthMiddleware`).

### Controller Structure
Each `RouteCollection` owns its own route prefix and all CRUD for one resource:
- `BoardController` — `/boards` — board CRUD, member invite/remove, import/export
- `ColumnController` — `/columns` — column CRUD + reorder
- `CardController` — `/cards` — card CRUD + move between columns
- `AuthController` — registration, login, password reset
- `UserController` — profile, avatar, account deletion
- `AdminController` — admin-only user/invite management (behind `AdminMiddleware`)

### HTMX Integration
Controllers check `req.headers.contains(name: "HX-Request")` to return partial HTML fragments (Leaf partials) instead of full pages. This is the primary mechanism for in-place updates without full page reloads.

### Email
`EmailService` wraps the `Smtp` package. If `SMTP_PASSWORD` is not set, all email calls fall back to log output — no SMTP dependency for local development.

### Invite System
Registration is invite-only. Board owners send email invites via `POST /boards/:boardID/members`. If the invitee already has an account they're added directly; otherwise an `InviteCode` record is created and emailed. Users have an `inviteCredits` field that regenerates over time (`User.regenerateInviteCredits()`).

## Key Environment Variables

| Variable | Purpose | Default |
|---|---|---|
| `DATABASE_HOST` | Enables Postgres mode | — (SQLite if absent) |
| `JWT_SECRET` | HS256 signing key | `development-secret-only` |
| `ADMIN_EMAIL` | Grants admin on startup | — |
| `BASE_URL` | Used in email links | `http://localhost:8080` |
| `SMTP_*` | Email sending | Falls back to log if absent |
