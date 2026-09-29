import { q } from './db.js';
import { broadcast } from './realtime.js';
import { translate, translationEnabled } from './translate.js';

// Languages people in this trip read (tourists + the company's staff).
async function readerLanguages(tripId) {
  const { rows } = await q(
    `SELECT language FROM members WHERE trip_id=$1
     UNION SELECT s.language FROM staff s JOIN trips t ON t.company_id=s.company_id WHERE t.id=$1`, [tripId]);
  return rows.map((r) => r.language);
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/**
 * Translate a stored message for every reader language and push each result live.
 * Runs in the background; the original message is already delivered.
 * System messages may still be inside an open transaction, so inserts retry briefly.
 */
export async function translateInBackground(msg) {
  if (!translationEnabled()) return;
  try {
    const targets = await readerLanguages(msg.trip_id);
    const out = await translate(msg.body, msg.lang, targets);
    for (const [lang, body] of Object.entries(out)) {
      for (let attempt = 0; ; attempt++) {
        try {
          await q(`INSERT INTO message_translations(message_id, lang, body) VALUES ($1,$2,$3) ON CONFLICT DO NOTHING`, [msg.id, lang, body]);
          break;
        } catch (e) {
          if (e.code !== '23503' || attempt >= 5) throw e; // FK: message not committed yet
          await sleep(300);
        }
      }
      broadcast(msg.trip_id, 'translation', { messageId: msg.id, lang, body });
    }
    if (Object.keys(out).length) {
      await q(
        `INSERT INTO translation_usage(company_id, month, messages)
         SELECT company_id, date_trunc('month', now())::date, 1 FROM trips WHERE id=$1
         ON CONFLICT (company_id, month) DO UPDATE SET messages = translation_usage.messages + 1`, [msg.trip_id]);
    }
  } catch (e) {
    console.error('translateInBackground', e.message);
  }
}
