import { Router } from 'express';
import db from '../db.js';
import { authMiddleware } from '../auth.js';

const router = Router();
router.use(authMiddleware);

router.post('/:id/vote', (req, res) => {
  const pollId = parseInt(req.params.id, 10);
  const { option_index, option_indexes } = req.body;
  const me = req.user.userId;
  if (Number.isNaN(pollId)) return res.status(400).json({ error: 'Некорректный id опроса' });

  const poll = db.prepare('SELECT id, message_id, options, multiple FROM polls WHERE id = ?').get(pollId);
  if (!poll) return res.status(404).json({ error: 'Опрос не найден' });

  const options = JSON.parse(poll.options || '[]');
  const indices = option_indexes != null && Array.isArray(option_indexes)
    ? option_indexes.map(x => parseInt(x, 10)).filter(i => !Number.isNaN(i) && i >= 0 && i < options.length)
    : (option_index != null && !Number.isNaN(parseInt(option_index, 10)))
      ? [parseInt(option_index, 10)]
      : [];
  const idx = indices[0];
  if (poll.multiple) {
    if (indices.length === 0) return res.status(400).json({ error: 'Выберите вариант(ы)' });
  } else {
    if (indices.length !== 1 || idx < 0 || idx >= options.length) return res.status(400).json({ error: 'Выберите один вариант' });
  }

  const msg = db.prepare('SELECT sender_id, receiver_id FROM messages WHERE id = ?').get(poll.message_id);
  if (!msg || (msg.sender_id !== me && msg.receiver_id !== me)) return res.status(403).json({ error: 'Нет доступа к этому опросу' });

  const insertVote = db.prepare('INSERT INTO poll_votes (poll_id, user_id, option_index) VALUES (?, ?, ?)');
  db.prepare('DELETE FROM poll_votes WHERE poll_id = ? AND user_id = ?').run(pollId, me);
  if (poll.multiple) {
    for (const i of indices) {
      if (i >= 0 && i < options.length) insertVote.run(pollId, me, i);
    }
  } else {
    insertVote.run(pollId, me, idx);
  }

  const votes = db.prepare('SELECT option_index, user_id FROM poll_votes WHERE poll_id = ?').all(pollId);
  const counts = options.map((_, i) => votes.filter(v => v.option_index === i).length);
  const myVotes = votes.filter(v => v.user_id === me).map(v => v.option_index);
  res.json({
    poll_id: pollId,
    options: options.map((text, i) => ({ text, votes: counts[i], voted: myVotes.includes(i) })),
  });
});

export default router;
