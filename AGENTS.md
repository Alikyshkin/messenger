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
- **In-memory test DB bug**: The default `npm test` command uses `MESSENGER_DB_PATH=:memory:` which causes a `SqliteError: no such column: email` because the migration runner and `db.js` open separate in-memory databases. To work around this, use a file-based temp path: `NODE_ENV=test MESSENGER_DB_PATH=/tmp/test-messenger.db JWT_SECRET=test-secret node --test tests/auth.test.js tests/api.test.js tests/websocket.test.js tests/e2e/chat_e2e.test.js tests/smoke/smoke.test.js`. Delete the temp DB between runs with `rm -f /tmp/test-messenger.db`.
- **Pre-existing test failures**: Several tests fail due to password validation changes and messaging privacy checks that the tests don't account for. This is a codebase issue, not an environment issue.
- **Friend requests workflow**: `POST /contacts` sends a friend request (not a direct add). The recipient must call `POST /contacts/requests/:id/accept` before users appear as mutual contacts and can message each other.
- **Privacy defaults**: New users default to `who_can_message: 'contacts'`, so messaging requires mutual contact status.
- **SQLite database**: Embedded via `better-sqlite3`; no external database service needed. Data stored in `server/messenger.db` (auto-created on first run).
- **Redis/FCM/SMTP**: All optional. Server starts and works fully without them.

### Client (Flutter)

Flutter SDK is required to build/test the client but is not installed in this environment. Server-side development and testing works independently.
