import crypto from 'crypto';

const ALGO = 'aes-256-gcm';
const IV_LEN = 16;
const AUTH_TAG_LEN = 16;
const KEY_LEN = 32;
const PREFIX = 'enc:';

function getKey() {
  const raw = process.env.ENCRYPTION_KEY;
  if (!raw || raw.length < 16) return null;
  return crypto.createHash('sha256').update(raw, 'utf8').digest();
}

export function encrypt(plaintext) {
  const key = getKey();
  if (!key) return plaintext;
  const iv = crypto.randomBytes(IV_LEN);
  const cipher = crypto.createCipheriv(ALGO, key, iv);
  const enc = Buffer.concat([cipher.update(plaintext, 'utf8'), cipher.final()]);
  const tag = cipher.getAuthTag();
  const combined = Buffer.concat([iv, tag, enc]);
  return PREFIX + combined.toString('base64');
}

export function decrypt(ciphertext) {
  if (typeof ciphertext !== 'string' || !ciphertext.startsWith(PREFIX)) {
    return ciphertext;
  }
  const key = getKey();
  if (!key) return ciphertext;
  try {
    const buf = Buffer.from(ciphertext.slice(PREFIX.length), 'base64');
    const iv = buf.subarray(0, IV_LEN);
    const tag = buf.subarray(IV_LEN, IV_LEN + AUTH_TAG_LEN);
    const enc = buf.subarray(IV_LEN + AUTH_TAG_LEN);
    const decipher = crypto.createDecipheriv(ALGO, key, iv);
    decipher.setAuthTag(tag);
    return decipher.update(enc) + decipher.final('utf8');
  } catch {
    return ciphertext;
  }
}

/** For E2EE: return as-is. For legacy server-encrypted content (enc:...), decrypt. */
export function decryptIfLegacy(ciphertext) {
  if (typeof ciphertext !== 'string') return ciphertext;
  if (!ciphertext.startsWith(PREFIX)) return ciphertext;
  return decrypt(ciphertext);
}
