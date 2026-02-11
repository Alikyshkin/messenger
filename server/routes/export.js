import { Router } from 'express';
import db from '../db.js';
import { authMiddleware } from '../auth.js';
import { decryptIfLegacy } from '../cipher.js';
import { escapeHtml } from '../middleware/sanitize.js';
import { asyncHandler } from '../middleware/errorHandler.js';

const router = Router();
router.use(authMiddleware);

function getBaseUrl(req) {
  const proto = req.get('x-forwarded-proto') || req.protocol || 'http';
  const host = req.get('host') || 'localhost:3000';
  return `${proto}://${host}`;
}

/**
 * Экспорт данных пользователя в JSON
 * GET /export/json
 */
router.get('/json', asyncHandler(async (req, res) => {
  const me = req.user.userId;
  const baseUrl = getBaseUrl(req);
  
  // Получаем профиль пользователя
  const user = db.prepare(
    'SELECT id, username, display_name, bio, email, birthday, phone, created_at, is_online, last_seen FROM users WHERE id = ?'
  ).get(me);
  
  // Получаем контакты
  const contacts = db.prepare(`
    SELECT u.id, u.username, u.display_name, u.bio, u.created_at
    FROM contacts c
    JOIN users u ON u.id = c.contact_id
    WHERE c.user_id = ?
    ORDER BY u.display_name, u.username
  `).all(me);
  
  // Получаем личные сообщения
  const messages = db.prepare(`
    SELECT id, sender_id, receiver_id, content, created_at, read_at, attachment_path, 
           attachment_filename, message_type, attachment_kind, attachment_duration_sec,
           attachment_encrypted, reply_to_id, is_forwarded, forward_from_sender_id,
           forward_from_display_name
    FROM messages
    WHERE sender_id = ? OR receiver_id = ?
    ORDER BY created_at
  `).all(me, me);
  
  // Получаем группы
  const groups = db.prepare(`
    SELECT g.id, g.name, g.created_at, gm.role
    FROM groups g
    JOIN group_members gm ON g.id = gm.group_id
    WHERE gm.user_id = ?
  `).all(me);
  
  // Получаем сообщения в группах
  const groupMessages = db.prepare(`
    SELECT gm.id, gm.group_id, gm.sender_id, gm.content, gm.created_at,
           gm.attachment_path, gm.attachment_filename, gm.message_type,
           gm.attachment_kind, gm.attachment_duration_sec, gm.attachment_encrypted,
           gm.reply_to_id, gm.is_forwarded, gm.forward_from_sender_id,
           gm.forward_from_display_name
    FROM group_messages gm
    JOIN group_members gmem ON gm.group_id = gmem.group_id
    WHERE gmem.user_id = ?
    ORDER BY gm.created_at
  `).all(me);
  
  // Формируем данные для экспорта
  const exportData = {
    export_date: new Date().toISOString(),
    user: {
      id: user.id,
      username: user.username,
      display_name: user.display_name || user.username,
      bio: user.bio ?? null,
      email: user.email ?? null,
      birthday: user.birthday ?? null,
      phone: user.phone ?? null,
      created_at: user.created_at,
      is_online: !!(user.is_online),
      last_seen: user.last_seen || null,
    },
    contacts: contacts.map(c => ({
      id: c.id,
      username: c.username,
      display_name: c.display_name || c.username,
      bio: c.bio ?? null,
      created_at: c.created_at,
    })),
    messages: messages.map(m => ({
      id: m.id,
      sender_id: m.sender_id,
      receiver_id: m.receiver_id,
      content: decryptIfLegacy(m.content),
      created_at: m.created_at,
      read_at: m.read_at || null,
      attachment_url: m.attachment_path ? `${baseUrl}/uploads/${m.attachment_path}` : null,
      attachment_filename: m.attachment_filename || null,
      message_type: m.message_type || 'text',
      attachment_kind: m.attachment_kind || 'file',
      attachment_duration_sec: m.attachment_duration_sec ?? null,
      attachment_encrypted: !!(m.attachment_encrypted),
      reply_to_id: m.reply_to_id ?? null,
      is_forwarded: !!(m.is_forwarded),
      forward_from_sender_id: m.forward_from_sender_id ?? null,
      forward_from_display_name: m.forward_from_display_name ?? null,
    })),
    groups: groups.map(g => ({
      id: g.id,
      name: g.name,
      role: g.role,
      created_at: g.created_at,
    })),
    group_messages: groupMessages.map(gm => ({
      id: gm.id,
      group_id: gm.group_id,
      sender_id: gm.sender_id,
      content: decryptIfLegacy(gm.content),
      created_at: gm.created_at,
      attachment_url: gm.attachment_path ? `${baseUrl}/uploads/${gm.attachment_path}` : null,
      attachment_filename: gm.attachment_filename || null,
      message_type: gm.message_type || 'text',
      attachment_kind: gm.attachment_kind || 'file',
      attachment_duration_sec: gm.attachment_duration_sec ?? null,
      attachment_encrypted: !!(gm.attachment_encrypted),
      reply_to_id: gm.reply_to_id ?? null,
      is_forwarded: !!(gm.is_forwarded),
      forward_from_sender_id: gm.forward_from_sender_id ?? null,
      forward_from_display_name: gm.forward_from_display_name ?? null,
    })),
  };
  
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.setHeader('Content-Disposition', `attachment; filename="messenger_export_${Date.now()}.json"`);
  res.json(exportData);
}));

/**
 * Экспорт данных пользователя в HTML
 * GET /export/html
 */
router.get('/html', asyncHandler(async (req, res) => {
  const me = req.user.userId;
  const baseUrl = getBaseUrl(req);
  
  // Получаем те же данные, что и для JSON
  const user = db.prepare(
    'SELECT id, username, display_name, bio, email, birthday, phone, created_at, is_online, last_seen FROM users WHERE id = ?'
  ).get(me);
  
  const contacts = db.prepare(`
    SELECT u.id, u.username, u.display_name, u.bio, u.created_at
    FROM contacts c
    JOIN users u ON u.id = c.contact_id
    WHERE c.user_id = ?
    ORDER BY u.display_name, u.username
  `).all(me);
  
  const messages = db.prepare(`
    SELECT id, sender_id, receiver_id, content, created_at, read_at, attachment_path, 
           attachment_filename, message_type
    FROM messages
    WHERE sender_id = ? OR receiver_id = ?
    ORDER BY created_at
  `).all(me, me);
  
  const groups = db.prepare(`
    SELECT g.id, g.name, g.created_at, gm.role
    FROM groups g
    JOIN group_members gm ON g.id = gm.group_id
    WHERE gm.user_id = ?
  `).all(me);
  
  const groupMessages = db.prepare(`
    SELECT gm.id, gm.group_id, gm.sender_id, gm.content, gm.created_at,
           gm.attachment_path, gm.attachment_filename, gm.message_type
    FROM group_messages gm
    JOIN group_members gmem ON gm.group_id = gmem.group_id
    WHERE gmem.user_id = ?
    ORDER BY gm.created_at
  `).all(me);
  
  // Получаем имена пользователей для отображения
  const getUserName = (userId) => {
    const u = db.prepare('SELECT display_name, username FROM users WHERE id = ?').get(userId);
    return u ? (u.display_name || u.username) : 'Неизвестный';
  };
  
  const getGroupName = (groupId) => {
    const g = db.prepare('SELECT name FROM groups WHERE id = ?').get(groupId);
    return g ? g.name : 'Неизвестная группа';
  };
  
  // Формируем HTML
  const html = `<!DOCTYPE html>
<html lang="ru">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Экспорт данных мессенджера</title>
  <style>
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      max-width: 1200px;
      margin: 0 auto;
      padding: 20px;
      background: #f5f5f5;
    }
    h1 { color: #333; border-bottom: 2px solid #007bff; padding-bottom: 10px; }
    h2 { color: #555; margin-top: 30px; }
    .section { background: white; padding: 20px; margin: 20px 0; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
    .user-info { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 10px; }
    .user-info div { padding: 8px; background: #f8f9fa; border-radius: 4px; }
    .user-info strong { color: #007bff; }
    table { width: 100%; border-collapse: collapse; margin-top: 15px; }
    th, td { padding: 12px; text-align: left; border-bottom: 1px solid #ddd; }
    th { background: #007bff; color: white; }
    tr:hover { background: #f8f9fa; }
    .message-content { max-width: 400px; word-wrap: break-word; }
    .attachment { color: #007bff; }
    .meta { color: #666; font-size: 0.9em; }
  </style>
</head>
<body>
  <h1>Экспорт данных мессенджера</h1>
  <p class="meta">Дата экспорта: ${new Date().toLocaleString('ru-RU')}</p>
  
  <div class="section">
    <h2>Профиль пользователя</h2>
    <div class="user-info">
      <div><strong>ID:</strong> ${escapeHtml(String(user.id))}</div>
      <div><strong>Имя пользователя:</strong> ${escapeHtml(user.username)}</div>
      <div><strong>Отображаемое имя:</strong> ${escapeHtml(user.display_name || user.username)}</div>
      <div><strong>Биография:</strong> ${user.bio ? escapeHtml(user.bio) : '—'}</div>
      <div><strong>Email:</strong> ${user.email ? escapeHtml(user.email) : '—'}</div>
      <div><strong>День рождения:</strong> ${user.birthday ? escapeHtml(user.birthday) : '—'}</div>
      <div><strong>Телефон:</strong> ${user.phone ? escapeHtml(user.phone) : '—'}</div>
      <div><strong>Дата регистрации:</strong> ${new Date(user.created_at).toLocaleString('ru-RU')}</div>
      <div><strong>Статус:</strong> ${user.is_online ? 'Онлайн' : 'Офлайн'}</div>
      <div><strong>Последний визит:</strong> ${user.last_seen ? new Date(user.last_seen).toLocaleString('ru-RU') : '—'}</div>
    </div>
  </div>
  
  <div class="section">
    <h2>Контакты (${contacts.length})</h2>
    <table>
      <thead>
        <tr>
          <th>ID</th>
          <th>Имя пользователя</th>
          <th>Отображаемое имя</th>
          <th>Биография</th>
          <th>Дата регистрации</th>
        </tr>
      </thead>
      <tbody>
        ${contacts.map(c => `
          <tr>
            <td>${escapeHtml(String(c.id))}</td>
            <td>${escapeHtml(c.username)}</td>
            <td>${escapeHtml(c.display_name || c.username)}</td>
            <td>${c.bio ? escapeHtml(c.bio) : '—'}</td>
            <td>${new Date(c.created_at).toLocaleString('ru-RU')}</td>
          </tr>
        `).join('')}
      </tbody>
    </table>
  </div>
  
  <div class="section">
    <h2>Личные сообщения (${messages.length})</h2>
    <table>
      <thead>
        <tr>
          <th>ID</th>
          <th>От</th>
          <th>К</th>
          <th>Содержание</th>
          <th>Дата</th>
          <th>Прочитано</th>
          <th>Вложение</th>
        </tr>
      </thead>
      <tbody>
        ${messages.map(m => {
          const senderName = getUserName(m.sender_id);
          const receiverName = getUserName(m.receiver_id);
          const content = decryptIfLegacy(m.content);
          const attachment = m.attachment_path ? `<span class="attachment">${escapeHtml(m.attachment_filename || 'Файл')}</span>` : '—';
          return `
          <tr>
            <td>${escapeHtml(String(m.id))}</td>
            <td>${escapeHtml(senderName)}</td>
            <td>${escapeHtml(receiverName)}</td>
            <td class="message-content">${escapeHtml(content.substring(0, 100))}${content.length > 100 ? '...' : ''}</td>
            <td>${new Date(m.created_at).toLocaleString('ru-RU')}</td>
            <td>${m.read_at ? new Date(m.read_at).toLocaleString('ru-RU') : 'Нет'}</td>
            <td>${attachment}</td>
          </tr>
        `;
        }).join('')}
      </tbody>
    </table>
  </div>
  
  <div class="section">
    <h2>Группы (${groups.length})</h2>
    <table>
      <thead>
        <tr>
          <th>ID</th>
          <th>Название</th>
          <th>Роль</th>
          <th>Дата создания</th>
        </tr>
      </thead>
      <tbody>
        ${groups.map(g => `
          <tr>
            <td>${escapeHtml(String(g.id))}</td>
            <td>${escapeHtml(g.name)}</td>
            <td>${g.role === 'admin' ? 'Администратор' : 'Участник'}</td>
            <td>${new Date(g.created_at).toLocaleString('ru-RU')}</td>
          </tr>
        `).join('')}
      </tbody>
    </table>
  </div>
  
  <div class="section">
    <h2>Сообщения в группах (${groupMessages.length})</h2>
    <table>
      <thead>
        <tr>
          <th>ID</th>
          <th>Группа</th>
          <th>Отправитель</th>
          <th>Содержание</th>
          <th>Дата</th>
          <th>Вложение</th>
        </tr>
      </thead>
      <tbody>
        ${groupMessages.map(gm => {
          const senderName = getUserName(gm.sender_id);
          const groupName = getGroupName(gm.group_id);
          const content = decryptIfLegacy(gm.content);
          const attachment = gm.attachment_path ? `<span class="attachment">${escapeHtml(gm.attachment_filename || 'Файл')}</span>` : '—';
          return `
          <tr>
            <td>${escapeHtml(String(gm.id))}</td>
            <td>${escapeHtml(groupName)}</td>
            <td>${escapeHtml(senderName)}</td>
            <td class="message-content">${escapeHtml(content.substring(0, 100))}${content.length > 100 ? '...' : ''}</td>
            <td>${new Date(gm.created_at).toLocaleString('ru-RU')}</td>
            <td>${attachment}</td>
          </tr>
        `;
        }).join('')}
      </tbody>
    </table>
  </div>
</body>
</html>`;
  
  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  res.setHeader('Content-Disposition', `attachment; filename="messenger_export_${Date.now()}.html"`);
  res.send(html);
}));

export default router;
