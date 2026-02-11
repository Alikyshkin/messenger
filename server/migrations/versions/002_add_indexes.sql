-- Миграция 002: Добавление индексов для оптимизации производительности

-- Индексы для таблицы messages
CREATE INDEX IF NOT EXISTS idx_messages_sender_receiver ON messages(sender_id, receiver_id);
CREATE INDEX IF NOT EXISTS idx_messages_receiver_read ON messages(receiver_id, read_at);
CREATE INDEX IF NOT EXISTS idx_messages_created_desc ON messages(created_at DESC);

-- Индексы для таблицы contacts
CREATE INDEX IF NOT EXISTS idx_contacts_contact ON contacts(contact_id);

-- Индексы для таблицы group_messages
CREATE INDEX IF NOT EXISTS idx_group_messages_group_created ON group_messages(group_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_group_messages_sender ON group_messages(sender_id);

-- Индексы для таблицы group_members
CREATE INDEX IF NOT EXISTS idx_group_members_group ON group_members(group_id);
CREATE INDEX IF NOT EXISTS idx_group_members_group_user ON group_members(group_id, user_id);

-- Индексы для таблицы group_read
CREATE INDEX IF NOT EXISTS idx_group_read_user ON group_read(user_id);

-- Индексы для таблицы message_reactions
CREATE INDEX IF NOT EXISTS idx_message_reactions_user ON message_reactions(user_id);

-- Индексы для таблицы group_message_reactions
CREATE INDEX IF NOT EXISTS idx_group_message_reactions_user ON group_message_reactions(user_id);

-- Индексы для таблицы poll_votes
CREATE INDEX IF NOT EXISTS idx_poll_votes_user ON poll_votes(user_id);
CREATE INDEX IF NOT EXISTS idx_poll_votes_poll_user ON poll_votes(poll_id, user_id);

-- Индексы для таблицы group_poll_votes
CREATE INDEX IF NOT EXISTS idx_group_poll_votes_user ON group_poll_votes(user_id);
CREATE INDEX IF NOT EXISTS idx_group_poll_votes_poll_user ON group_poll_votes(poll_id, user_id);

-- Индексы для таблицы reset_tokens
CREATE INDEX IF NOT EXISTS idx_reset_tokens_user_expires ON reset_tokens(user_id, expires_at);

-- Индексы для таблицы friend_requests
CREATE INDEX IF NOT EXISTS idx_friend_requests_to_status ON friend_requests(to_user_id, status);
CREATE INDEX IF NOT EXISTS idx_friend_requests_from_to ON friend_requests(from_user_id, to_user_id);

-- Индексы для таблицы users
CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_users_phone ON users(phone);
