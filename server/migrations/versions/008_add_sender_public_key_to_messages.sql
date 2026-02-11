-- Храним публичный ключ отправителя на момент создания сообщения для E2EE.
-- Раньше ключ брали из users, из-за смены ключа старые сообщения не расшифровывались.
ALTER TABLE messages ADD COLUMN sender_public_key TEXT;

-- Заполняем существующие сообщения текущим ключом отправителя (best effort)
UPDATE messages SET sender_public_key = (SELECT public_key FROM users WHERE id = messages.sender_id) WHERE sender_public_key IS NULL;
