Project Overview
This is a full-stack Kanban board (Trello-style) built entirely in Swift using Vapor 4 (latest stable as of 2026) as the server-side framework. The backend handles authentication, data persistence (via Fluent ORM + PostgreSQL), real-time updates (WebSockets), and REST/HTMX endpoints. The frontend is server-rendered with Leaf templates for simplicity and speed, heavily enhanced with modern web technologies for a visually stunning, responsive, and interactive UI/UX.

Modern UI/UX highlights: Tailwind CSS v3+ (dark mode, glassmorphism accents, smooth hover lifts, micro-animations), HTMX + Alpine.js for SPA-like feel without a heavy JS framework, SortableJS for native-feeling drag-and-drop (with touch support), CSS transitions/keyframes, responsive grid layout, and optional PWA support.
Real-time collaboration via Vapor WebSockets (board updates broadcast to all connected users).
Deployment-ready: Docker + Docker Compose, async/await everywhere (Swift 6.0+), structured concurrency.

1. Project Build Structure (Standard Vapor + Web Template Layout)
Created with the official Vapor Toolbox (vapor new KanbanBoard --template web or the default API template + manual Leaf setup). The structure follows Swift Package Manager (SPM) conventions and is fully Xcode-friendly.
textKanbanBoard/
├── Package.swift                  # SPM manifest + dependencies
├── .env                           # Config (DB credentials, JWT secret)
├── .dockerignore
├── .gitignore
├── docker-compose.yml             # PostgreSQL + Redis (optional)
├── Dockerfile
│
├── Public/                        # Static assets served directly
│   ├── css/
│   │   └── app.css                # Tailwind output (or CDN + custom)
│   ├── js/
│   │   ├── sortable.js            # Drag-and-drop
│   │   ├── htmx.js
│   │   ├── alpine.js
│   │   └── board.js               # Custom drag-drop + WebSocket logic
│   └── images/                    # Avatars, icons
│
├── Resources/
│   └── Views/                     # Leaf templates
│       ├── base.leaf              # Layout with Tailwind + dark mode
│       ├── index.leaf             # Dashboard (board list)
│       ├── board.leaf             # Main Kanban view (columns + cards)
│       ├── partials/
│           ├── card.leaf
│           ├── column.leaf
│           └── navbar.leaf
│
├── Sources/
│   ├── App/                       # Main module
│   │   ├── app.swift              # Entry point (configure + run)
│   │   ├── configure.swift        # Middleware, DB, Leaf, WebSockets
│   │   ├── routes.swift           # All route registrations
│   │   ├── Controllers/
│   │   │   ├── BoardController.swift
│   │   │   ├── ColumnController.swift
│   │   │   ├── CardController.swift
│   │   │   └── AuthController.swift
│   │   ├── Models/
│   │   │   ├── User.swift
│   │   │   ├── Board.swift
│   │   │   ├── Column.swift
│   │   │   ├── Card.swift
│   │   │   ├── Label.swift
│   │   │   └── Comment.swift
│   │   ├── Migrations/            # Fluent migrations (all models + indexes)
│   │   ├── Middleware/
│   │   │   └── AuthMiddleware.swift
│   │   ├── Services/              # Repositories or WebSocket manager
│   │   │   └── WebSocketManager.swift
│   │   └── Extensions/            # Custom Vapor extensions
│   │
│   └── Run/                       # Executable target
│       └── main.swift             # @main App.run()
│
├── Tests/
│   └── AppTests/                  # Unit + integration tests
└── README.md
Build & Run Commands
Bashvapor build          # or swift build
vapor run            # or swift run Run serve
# Docker: docker-compose up --build
2. Key Dependencies (Package.swift)
Swiftdependencies: [
    .package(url: "https://github.com/vapor/vapor.git", from: "4.121.0"),
    .package(url: "https://github.com/vapor/fluent.git", from: "4.0.0"),
    .package(url: "https://github.com/vapor/fluent-postgres-driver.git", from: "2.0.0"),
    .package(url: "https://github.com/vapor/leaf.git", from: "4.0.0"),
    .package(url: "https://github.com/vapor/jwt.git", from: "4.0.0"),      // JWT auth
    .package(url: "https://github.com/vapor/redis.git", from: "4.0.0"),   // Optional caching
]
3. Core Models & Relationships (Fluent)

User (auth, name, avatar)
Board (title, owner, members – many-to-many)
Column (title e.g. “To Do”, position, boardID)
Card (title, description, position, dueDate, priority, assigneeID?, labels – many-to-many)
Label (name, color hex)
Comment (text, cardID, userID)

All models use async Fluent queries, soft deletes, timestamps, and proper indexes for performance.
4. Main Features
Core Kanban Functionality

Create/edit/delete unlimited boards
Dynamic columns (add, rename, reorder, delete)
Rich cards: title, Markdown description (planned), due dates (planned), priority badges, color labels, assignee avatars, checklists (future), attachments (future)
Drag & drop cards between columns + reordering within a column (real-time sync via WebSocket + optimistic UI)
Column reordering (native Drag & Drop)
Archive/Delete cards/columns

User & Collaboration

Secure registration/login (JWT + password hashing)
Multi-user boards with member invites
Real-time updates (WebSocket broadcasts on move, create, edit)
Activity feed (who moved what)

Advanced / Modern Touches

Search + filter cards (title, labels, assignee) (future)
Dark/light mode toggle (Tailwind + Alpine)
Unified User Settings (Profile, Appearance, Privacy)
Data Export (JSON format)
Account Deletion (Permanent data wipe)
Keyboard shortcuts (e.g. “N” for new card) (future)
Mobile-responsive (horizontal scroll on phone)
Static Content Pages (About, Contact, Docs, Privacy)
Email-enabled Contact Form
Notification system (future)
PWA support (future)

5. UI/UX Implementation – Visually Appealing & Modern

Layout: Flex/grid horizontal scroll for columns; each column is a droppable zone with subtle gradient background.
Cards: Rounded-xl, subtle shadow + hover lift (scale + shadow transition), glassmorphism header, colored label pills, smooth fade-in animations.
Drag & Drop: SortableJS + HTMX – on end event it sends a PATCH request (/cards/{id}/move) with new column + position. Instant visual feedback + WebSocket confirmation.
Styling: Tailwind + custom CSS variables for theme switching. Glassmorphism accents on modals, neumorphic buttons optional.
Interactivity: HTMX for all CRUD (no full page reloads), Alpine.js for dropdowns/modals, WebSocket connection in board.js for live updates.
Accessibility: ARIA labels, keyboard drag support, high contrast.

Example Leaf snippet (card partial):
leaf<div class="card bg-white dark:bg-zinc-800 shadow-xl hover:shadow-2xl transition-all rounded-3xl p-5 cursor-grab" 
     hx-post="/cards/#(card.id)/move" ...>
    <!-- rich content -->
</div>
6. Routes & Architecture Highlights

REST endpoints (/api/boards, /api/cards) + HTMX-friendly routes that return partial HTML.
WebSocket route: /board/{boardID}/live
All controllers use async/await + repository pattern for clean code.
Middleware: Auth, CORS, rate limiting.
Validation with Vapor’s built-in validators.

