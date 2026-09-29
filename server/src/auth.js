import { scrypt, randomBytes, timingSafeEqual, randomInt } from 'node:crypto';
import { promisify } from 'node:util';
import jwt from 'jsonwebtoken';
import { config } from './config.js';

const scryptAsync = promisify(scrypt);

export async function hashPassword(pw) {
  const salt = randomBytes(16);
  const key = await scryptAsync(pw, salt, 64);
  return `scrypt$${salt.toString('hex')}$${key.toString('hex')}`;
}

export async function verifyPassword(pw, stored) {
  const [, saltHex, keyHex] = stored.split('$');
  const key = await scryptAsync(pw, Buffer.from(saltHex, 'hex'), 64);
  return timingSafeEqual(key, Buffer.from(keyHex, 'hex'));
}

// kind: 'staff' (guide/admin) or 'member' (tourist joined by code)
export const sign = (payload) => jwt.sign(payload, config.jwtSecret, { expiresIn: '30d' });
export const verify = (token) => jwt.verify(token, config.jwtSecret);

// No 0/O/1/I so codes are easy to read aloud.
const ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
export function randomCode(len = 6) {
  let s = '';
  for (let i = 0; i < len; i++) s += ALPHABET[randomInt(ALPHABET.length)];
  return s;
}

export function requireAuth(kind) {
  return (req, res, next) => {
    const h = req.headers.authorization ?? '';
    try {
      const p = verify(h.replace(/^Bearer /, ''));
      if (kind && p.kind !== kind) return res.status(403).json({ error: 'forbidden' });
      req.auth = p;
      next();
    } catch {
      res.status(401).json({ error: 'unauthorized' });
    }
  };
}
