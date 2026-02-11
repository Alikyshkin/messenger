import db from '../db.js';
import { log } from './logger.js';

/**
 * Утилиты для оптимизации запросов к БД
 * Предотвращение N+1 проблем
 */

/**
 * Получить пользователей по списку ID одним запросом
 */
export function getUsersByIds(userIds) {
  if (!userIds || userIds.length === 0) {
    return [];
  }
  
  const placeholders = userIds.map(() => '?').join(',');
  const users = db.prepare(`
    SELECT id, username, display_name, bio, avatar_path, created_at, public_key, 
           email, birthday, phone, is_online, last_seen
    FROM users
    WHERE id IN (${placeholders})
  `).all(...userIds);
  
  // Создаём Map для быстрого доступа
  const userMap = new Map();
  users.forEach(user => {
    userMap.set(user.id, user);
  });
  
  return userMap;
}

/**
 * Получить реакции для списка сообщений одним запросом
 */
export function getReactionsForMessages(messageIds) {
  if (!messageIds || messageIds.length === 0) {
    return new Map();
  }
  
  const placeholders = messageIds.map(() => '?').join(',');
  const reactions = db.prepare(`
    SELECT message_id, user_id, emoji
    FROM message_reactions
    WHERE message_id IN (${placeholders})
  `).all(...messageIds);
  
  // Группируем по message_id
  const reactionsMap = new Map();
  reactions.forEach(reaction => {
    if (!reactionsMap.has(reaction.message_id)) {
      reactionsMap.set(reaction.message_id, []);
    }
    reactionsMap.get(reaction.message_id).push({
      user_id: reaction.user_id,
      emoji: reaction.emoji,
    });
  });
  
  return reactionsMap;
}

/**
 * Получить реакции для групповых сообщений одним запросом
 */
export function getGroupReactionsForMessages(messageIds) {
  if (!messageIds || messageIds.length === 0) {
    return new Map();
  }
  
  const placeholders = messageIds.map(() => '?').join(',');
  const reactions = db.prepare(`
    SELECT group_message_id as message_id, user_id, emoji
    FROM group_message_reactions
    WHERE group_message_id IN (${placeholders})
  `).all(...messageIds);
  
  // Группируем по message_id
  const reactionsMap = new Map();
  reactions.forEach(reaction => {
    if (!reactionsMap.has(reaction.message_id)) {
      reactionsMap.set(reaction.message_id, []);
    }
    reactionsMap.get(reaction.message_id).push({
      user_id: reaction.user_id,
      emoji: reaction.emoji,
    });
  });
  
  return reactionsMap;
}

/**
 * Получить опросы для сообщений одним запросом
 */
export function getPollsForMessages(messageIds) {
  if (!messageIds || messageIds.length === 0) {
    return new Map();
  }
  
  const placeholders = messageIds.map(() => '?').join(',');
  const polls = db.prepare(`
    SELECT p.id, p.message_id, p.question, p.options, p.multiple
    FROM polls p
    WHERE p.message_id IN (${placeholders})
  `).all(...messageIds);
  
  const pollsMap = new Map();
  polls.forEach(poll => {
    pollsMap.set(poll.message_id, {
      id: poll.id,
      question: poll.question,
      options: JSON.parse(poll.options || '[]'),
      multiple: !!poll.multiple,
    });
  });
  
  // Получаем голоса для всех опросов
  if (polls.length > 0) {
    const pollIds = polls.map(p => p.id);
    const pollPlaceholders = pollIds.map(() => '?').join(',');
    const votes = db.prepare(`
      SELECT poll_id, user_id, option_index
      FROM poll_votes
      WHERE poll_id IN (${pollPlaceholders})
    `).all(...pollIds);
    
    // Группируем голоса по poll_id и option_index
    const votesMap = new Map();
    votes.forEach(vote => {
      const key = `${vote.poll_id}_${vote.option_index}`;
      if (!votesMap.has(key)) {
        votesMap.set(key, []);
      }
      votesMap.get(key).push(vote.user_id);
    });
    
    // Добавляем голоса к опросам
    pollsMap.forEach((poll, messageId) => {
      const pollId = polls.find(p => p.message_id === messageId)?.id;
      if (pollId) {
        poll.options = poll.options.map((option, index) => {
          const key = `${pollId}_${index}`;
          return {
            text: option,
            votes: votesMap.get(key)?.length || 0,
            voted: false, // Будет установлено на уровне вызывающего кода
          };
        });
      }
    });
  }
  
  return pollsMap;
}

/**
 * Получить опросы для групповых сообщений одним запросом
 */
export function getGroupPollsForMessages(messageIds) {
  if (!messageIds || messageIds.length === 0) {
    return new Map();
  }
  
  const placeholders = messageIds.map(() => '?').join(',');
  const polls = db.prepare(`
    SELECT p.id, p.group_message_id as message_id, p.question, p.options, p.multiple
    FROM group_polls p
    WHERE p.group_message_id IN (${placeholders})
  `).all(...messageIds);
  
  const pollsMap = new Map();
  polls.forEach(poll => {
    pollsMap.set(poll.message_id, {
      id: poll.id,
      question: poll.question,
      options: JSON.parse(poll.options || '[]'),
      multiple: !!poll.multiple,
    });
  });
  
  // Получаем голоса для всех опросов
  if (polls.length > 0) {
    const pollIds = polls.map(p => p.id);
    const pollPlaceholders = pollIds.map(() => '?').join(',');
    const votes = db.prepare(`
      SELECT group_poll_id as poll_id, user_id, option_index
      FROM group_poll_votes
      WHERE group_poll_id IN (${pollPlaceholders})
    `).all(...pollIds);
    
    // Группируем голоса по poll_id и option_index
    const votesMap = new Map();
    votes.forEach(vote => {
      const key = `${vote.poll_id}_${vote.option_index}`;
      if (!votesMap.has(key)) {
        votesMap.set(key, []);
      }
      votesMap.get(key).push(vote.user_id);
    });
    
    // Добавляем голоса к опросам
    pollsMap.forEach((poll, messageId) => {
      const pollId = polls.find(p => p.message_id === messageId)?.id;
      if (pollId) {
        poll.options = poll.options.map((option, index) => {
          const key = `${pollId}_${index}`;
          return {
            text: option,
            votes: votesMap.get(key)?.length || 0,
            voted: false, // Будет установлено на уровне вызывающего кода
          };
        });
      }
    });
  }
  
  return pollsMap;
}

/**
 * Измерить время выполнения запроса
 */
export function measureQuery(operation, queryFn) {
  const start = Date.now();
  try {
    const result = queryFn();
    const duration = Date.now() - start;
    
    if (duration > 100) { // Логируем медленные запросы (>100ms)
      log.warn({ operation, duration }, 'Slow query detected');
    }
    
    return result;
  } catch (error) {
    const duration = Date.now() - start;
    log.error({ error, operation, duration }, 'Query failed');
    throw error;
  }
}
