# AGENTS.md

## Cursor Cloud specific instructions

### Project overview

Cross-platform messenger (Node.js/Express backend + Flutter/Dart client). See `README.md` for the full overview and `docs/` for detailed documentation.

### Server (primary service)

- **Dev server**: `cd server && npm run dev` (uses `node --watch` for hot reload)
- **Tests**: `cd server && npm test` (uses Node.js built-in test runner with in-memory SQLite)
- **Lint**: `cd server && npm run lint` (not currently configured; echoes a warning)
- **API docs**: Available at `http://localhost:3000/api-docs/` when the server is running

### Important gotchas

- **`.env` file required**: Copy `server/.env.example` to `server/.env` before first run. The `JWT_SECRET` value from `.env.example` works for local development.
- **Friend requests workflow**: `POST /contacts` sends a friend request (not a direct add). The recipient must call `POST /contacts/requests/:id/accept` before users appear as mutual contacts and can message each other.
- **Privacy defaults**: New users default to `who_can_message: 'contacts'`, so messaging requires mutual contact status.
- **Password requirements**: Registration requires min 8 chars + zxcvbn score >= 2. Use passwords like `Str0ngP@ss!` in tests.
- **Rate limiting**: Disabled in `NODE_ENV=test`. In development, `registerLimiter` allows 3 registrations/hour/IP.
- **SQLite database**: Embedded via `better-sqlite3`; no external database service needed. Data stored in `server/messenger.db` (auto-created on first run).
- **Redis/FCM/SMTP**: All optional. Server starts and works fully without them.

### Client (Flutter)

Flutter SDK is required to build/test the client but is not installed in this environment. Server-side development and testing works independently.
