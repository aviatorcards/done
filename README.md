# Done. 💧

**A sleek, minimal, and lightning-fast Kanban board designed for small teams and personal projects.**

Built with the **Vapor** web framework (Swift), **HTMX**, and **Alpine.js**, Done. focuses on speed and a premium user experience without the bloat of modern enterprise tools.

![Done. Logo](Public/images/logo.png)

## ✨ Features

- ⚡ **Blazing Fast**: Near-instant page loads and interactions thanks to Vapor and HTMX.
- 🔄 **Real-time Sync**: Boards update in real-time across users via WebSockets.
- 🎨 **Stunning UI**: Modern glassmorphism design with a deep, easy-on-the-eyes dark mode.
- 📱 **Fully Responsive**: Works beautifully on desktop, tablet, and mobile.
- 🔒 **Secure Auth**: JWT-based authentication with secure cookie management.
- 🛡️ **Board Privacy**: Only board owners can access and modify their data.

## 🛠️ Tech Stack

- **Backend**: [Vapor](https://vapor.codes) (Swift 6.1)
- **Database**: [Fluent](https://docs.vapor.codes/fluent/overview/) ORM (SQLite for local, Postgres for Docker/Production)
- **Templating**: [Leaf](https://docs.vapor.codes/leaf/overview/)
- **Frontend**: 
  - [HTMX](https://htmx.org) for hypermedia-driven interactions
  - [Alpine.js](https://alpinejs.dev) for lightweight client-side reactivity
  - [Tailwind CSS](https://tailwindcss.com) for utility-first styling
  - [SortableJS](https://sortablejs.com) for smooth reordering

## 🚀 Getting Started

### Prerequisites

- [Swift 6.1+](https://www.swift.org/install/)
- [Docker](https://www.docker.com/) & [Docker Compose](https://docs.docker.com/compose/)

### Local Development (using SQLite)

1. **Clone & Build:**
   ```bash
   git clone https://github.com/aviatorcards/done.git
   cd done
   swift build
   ```

2. **Run:**
   ```bash
   swift run
   ```
   The site will be available at `http://127.0.0.1:8080`.

### Running with Docker Compose (Postgres)

Done. comes with a pre-configured `docker-compose.yml` for production-like environments using PostgreSQL.

1. **Build and start services:**
   ```bash
   docker compose up --build
   ```

2. **Run migrations (first time only):**
   ```bash
   docker compose run migrate
   ```

## 🔐 Registration Note

**Public registration is currently closed.** 
The login system remains active for existing users, but new account creation is restricted to maintain platform stability during this period.

---

Built with ❤️ for productivity.
