import db from '../db.js';

/** Кто может видеть статус: all, contacts, nobody */
export function canSeeStatus(viewerId, targetId) {
  if (viewerId === targetId) return true;
  const row = db.prepare('SELECT who_can_see_status FROM user_privacy WHERE user_id = ?').get(targetId);
  const setting = row?.who_can_see_status || 'contacts';
  if (setting === 'all') return true;
  if (setting === 'nobody') return false;
  const isContact = db.prepare('SELECT 1 FROM contacts WHERE user_id = ? AND contact_id = ?').get(targetId, viewerId);
  return !!isContact;
}

/** Кто может писать: all, contacts, nobody */
export function canMessage(senderId, receiverId) {
  const row = db.prepare('SELECT who_can_message FROM user_privacy WHERE user_id = ?').get(receiverId);
  const setting = row?.who_can_message || 'contacts';
  if (setting === 'all') return true;
  if (setting === 'nobody') return false;
  const isContact = db.prepare('SELECT 1 FROM contacts WHERE user_id = ? AND contact_id = ?').get(receiverId, senderId);
  return !!isContact;
}

/** Кто может звонить: all, contacts, nobody */
export function canCall(callerId, calleeId) {
  const row = db.prepare('SELECT who_can_call FROM user_privacy WHERE user_id = ?').get(calleeId);
  const setting = row?.who_can_call || 'contacts';
  if (setting === 'all') return true;
  if (setting === 'nobody') return false;
  const isContact = db.prepare('SELECT 1 FROM contacts WHERE user_id = ? AND contact_id = ?').get(calleeId, callerId);
  return !!isContact;
}
