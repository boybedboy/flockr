import express from 'express';
import { q, tx } from './db.js';
import { hashPassword, verifyPassword, sign, requireAuth, randomCode } from './auth.js';
import { isCareGroup, groupForAge, CARE_GROUPS } from './geo.js';
import { recordPosition, postSystemMessage } from './tracking.js';
import { broadcast } from './realtime.js';
import { LANGUAGES, isLanguage, translationEnabled } from './translate.js';
import { translateInBackground } from './chatTranslate.js';

const staff = requireAuth('staff');
const member = requireAuth('member');
const anyone = requireAuth();

const bad = (res, error, status = 400) => res.status(status).json({ error });
const isLatLng = (p) => p && Number.isFinite(p.lat) && Number.isFinite(p.lng)
  && Math.abs(p.lat) <= 90 && Math.abs(p.lng) <= 180;
const point = (p) => `SRID=4326;POINT(${p.lng} ${p.lat})`;

// Wrap async handlers so thrown errors reach the error middleware.
const h = (fn) => (req, res, next) => fn(req, res, next).catch(next);

async function staffTrip(req, res) {
  const { rows: [t] } = await q('SELECT * FROM trips WHERE id=$1 AND company_id=$2', [req.params.id, req.auth.companyId]);
  if (!t) bad(res, 'trip not found', 404);
  return t;
}

// Staff of the trip's company, or a member of that trip.
export async function canAccessTrip(auth, tripId) {
  if (!auth || !/^[0-9a-f-]{36}$/i.test(tripId ?? '')) return false;
  if (auth.kind === 'member') return auth.tripId === tripId;
  const { rowCount } = await q('SELECT 1 FROM trips WHERE id=$1 AND company_id=$2', [tripId, auth.companyId]);
  return rowCount > 0;
}

const MEMBER_COLS = `id, trip_id, name, care_group, device, fence_state, last_seen_at, checked_in_at,
  ST_Y(last_position::geometry) AS lat, ST_X(last_position::geometry) AS lng`;

export function createApp() {
  const app = express();
  app.use(express.json({ limit: '100kb' }));

  app.get('/health', (req, res) => res.json({ ok: true }));
  app.get('/api/care-groups', (req, res) => res.json(CARE_GROUPS));
  app.get('/api/languages', (req, res) => res.json({ languages: LANGUAGES, translation: translationEnabled() }));

  // The language this person reads chat in.
  app.put('/api/me/language', anyone, h(async (req, res) => {
    const { language } = req.body ?? {};
    if (!isLanguage(language)) return bad(res, `language must be one of ${Object.keys(LANGUAGES).join(', ')}`);
    await (req.auth.kind === 'staff'
      ? q('UPDATE staff SET language=$2 WHERE id=$1', [req.auth.staffId, language])
      : q('UPDATE members SET language=$2 WHERE id=$1', [req.auth.memberId, language]));
    res.json({ language });
  }));

  // ---------- staff accounts ----------
  app.post('/api/auth/signup', h(async (req, res) => {
    const { company, name, email, password } = req.body ?? {};
    if (!company || !name || !email || !password || password.length < 8) return bad(res, 'company, name, email and a password of 8+ characters are required');
    const out = await tx(async (db) => {
      const { rows: [c] } = await db.query('INSERT INTO companies(name) VALUES ($1) RETURNING id', [company]);
      const { rows: [s] } = await db.query(
        `INSERT INTO staff(company_id, email, password_hash, name, role) VALUES ($1,lower($2),$3,$4,'admin') RETURNING id, name, role`,
        [c.id, email, await hashPassword(password), name]);
      return { ...s, companyId: c.id };
    }).catch((e) => (e.code === '23505' ? null : Promise.reject(e)));
    if (!out) return bad(res, 'email already registered', 409);
    res.status(201).json({ token: sign({ kind: 'staff', staffId: out.id, companyId: out.companyId, role: out.role }), staff: out });
  }));

  app.post('/api/auth/login', h(async (req, res) => {
    const { email, password } = req.body ?? {};
    const { rows: [s] } = await q('SELECT * FROM staff WHERE email=lower($1)', [email ?? '']);
    if (!s || !(await verifyPassword(password ?? '', s.password_hash))) return bad(res, 'wrong email or password', 401);
    res.json({ token: sign({ kind: 'staff', staffId: s.id, companyId: s.company_id, role: s.role }), staff: { id: s.id, name: s.name, role: s.role, language: s.language } });
  }));

  // ---------- trips ----------
  app.post('/api/trips', staff, h(async (req, res) => {
    const { name, baseRadiusM = 300, centerMode = 'guide', fixedCenter, startsAt, endsAt } = req.body ?? {};
    if (!name) return bad(res, 'name is required');
    if (centerMode === 'fixed' && !isLatLng(fixedCenter)) return bad(res, 'fixedCenter {lat,lng} is required for a fixed centre');
    const trip = await tx(async (db) => {
      const { rows: [s] } = await db.query('SELECT name FROM staff WHERE id=$1', [req.auth.staffId]);
      const { rows: [t] } = await db.query(
        `INSERT INTO trips(company_id, guide_id, name, join_code, base_radius_m, center_mode, fixed_center, starts_at, ends_at)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9) RETURNING id, name, join_code, base_radius_m, center_mode`,
        [req.auth.companyId, req.auth.staffId, name, randomCode(), baseRadiusM, centerMode,
          centerMode === 'fixed' ? point(fixedCenter) : null, startsAt ?? null, endsAt ?? null]);
      // the guide is tracked as a special member row; it is the fence centre in "guide" mode
      await db.query(`INSERT INTO members(trip_id, name, care_group, consent_at) VALUES ($1,$2,'guide',now())`, [t.id, s.name]);
      return t;
    });
    res.status(201).json(trip);
  }));

  app.get('/api/trips', staff, h(async (req, res) => {
    const { rows } = await q(
      `SELECT t.id, t.name, t.join_code, t.base_radius_m, t.starts_at, t.ends_at,
              count(m.*) FILTER (WHERE m.care_group <> 'guide') AS members,
              count(m.*) FILTER (WHERE m.fence_state <> 'in') AS alerts
         FROM trips t LEFT JOIN members m ON m.trip_id=t.id
        WHERE t.company_id=$1 GROUP BY t.id ORDER BY t.created_at DESC`, [req.auth.companyId]);
    res.json(rows);
  }));

  app.get('/api/trips/:id', anyone, h(async (req, res) => {
    if (!(await canAccessTrip(req.auth, req.params.id))) return bad(res, 'trip not found', 404);
    const { rows: [trip] } = await q(
      `SELECT id, name, join_code, base_radius_m, center_mode,
              ST_Y(fixed_center::geometry) fixed_lat, ST_X(fixed_center::geometry) fixed_lng FROM trips WHERE id=$1`, [req.params.id]);
    const { rows: members } = await q(`SELECT ${MEMBER_COLS} FROM members WHERE trip_id=$1 ORDER BY created_at`, [req.params.id]);
    if (req.auth.kind === 'member') delete trip.join_code;
    res.json({ ...trip, members });
  }));

  app.patch('/api/trips/:id', staff, h(async (req, res) => {
    const t = await staffTrip(req, res); if (!t) return;
    const { baseRadiusM, centerMode, fixedCenter, name } = req.body ?? {};
    if (baseRadiusM != null && !(baseRadiusM >= 20 && baseRadiusM <= 5000)) return bad(res, 'baseRadiusM must be 20–5000');
    if (centerMode === 'fixed' && !isLatLng(fixedCenter)) return bad(res, 'fixedCenter {lat,lng} is required');
    const { rows: [u] } = await q(
      `UPDATE trips SET base_radius_m=COALESCE($2,base_radius_m), center_mode=COALESCE($3,center_mode),
         fixed_center=CASE WHEN $3='fixed' THEN $4::geography WHEN $3='guide' THEN NULL ELSE fixed_center END,
         name=COALESCE($5,name) WHERE id=$1 RETURNING id, name, base_radius_m, center_mode`,
      [t.id, baseRadiusM ?? null, centerMode ?? null, centerMode === 'fixed' ? point(fixedCenter) : null, name ?? null]);
    broadcast(t.id, 'trip', u);
    if (baseRadiusM != null) await postSystemMessage({ query: q }, t.id, `📍 ตั้งรัศมีผู้ใหญ่เป็น ${baseRadiusM} ม. กลุ่มอื่นคิดตามสัดส่วน`, { radius: baseRadiusM });
    res.json(u);
  }));

  app.post('/api/trips/:id/guide-position', staff, h(async (req, res) => {
    const t = await staffTrip(req, res); if (!t) return;
    if (!isLatLng(req.body)) return bad(res, 'lat and lng are required');
    const { rows: [g] } = await q(`SELECT id FROM members WHERE trip_id=$1 AND care_group='guide'`, [t.id]);
    res.json(await recordPosition(g.id, req.body));
  }));

  // ---------- members ----------
  function memberInput(b) {
    const careGroup = b.careGroup ?? (b.birthYear ? groupForAge(new Date().getFullYear() - b.birthYear) : 'adult');
    if (!isCareGroup(careGroup)) return { error: `careGroup must be one of ${Object.keys(CARE_GROUPS).join(', ')}` };
    if (!b.name) return { error: 'name is required' };
    if (!b.consent) return { error: 'consent to location tracking is required (PDPA)' };
    if (b.language && !isLanguage(b.language)) return { error: 'unsupported language' };
    return { careGroup };
  }
  const insertMember = (db, tripId, b, careGroup, device) => db.query(
    `INSERT INTO members(trip_id, name, care_group, birth_year, emergency_name, emergency_phone, medical_note, consent_at, device, language)
     VALUES ($1,$2,$3,$4,$5,$6,$7,now(),$8,$9) RETURNING ${MEMBER_COLS}, language`,
    [tripId, b.name, careGroup, b.birthYear ?? null, b.emergencyName ?? null, b.emergencyPhone ?? null, b.medicalNote ?? null, device, b.language ?? 'th']);

  // Tourist with a phone joins by code.
  app.post('/api/join', h(async (req, res) => {
    const b = req.body ?? {};
    const { rows: [t] } = await q('SELECT id, name FROM trips WHERE join_code=upper($1)', [b.code ?? '']);
    if (!t) return bad(res, 'join code not found', 404);
    const v = memberInput(b); if (v.error) return bad(res, v.error);
    const { rows: [m] } = await insertMember({ query: q }, t.id, b, v.careGroup, 'phone');
    broadcast(t.id, 'member', m);
    res.status(201).json({ token: sign({ kind: 'member', memberId: m.id, tripId: t.id }), member: m, trip: t });
  }));

  // Guide adds someone without a phone (they will get a card).
  app.post('/api/trips/:id/members', staff, h(async (req, res) => {
    const t = await staffTrip(req, res); if (!t) return;
    const v = memberInput(req.body ?? {}); if (v.error) return bad(res, v.error);
    const { rows: [m] } = await insertMember({ query: q }, t.id, req.body, v.careGroup, 'tag');
    broadcast(t.id, 'member', m);
    res.status(201).json(m);
  }));

  app.patch('/api/members/:mid', staff, h(async (req, res) => {
    const { careGroup, name } = req.body ?? {};
    if (careGroup && !isCareGroup(careGroup)) return bad(res, 'invalid careGroup');
    const { rows: [m] } = await q(
      `UPDATE members m SET care_group=COALESCE($3,care_group), name=COALESCE($4,name)
         FROM trips t WHERE m.id=$1 AND t.id=m.trip_id AND t.company_id=$2 AND m.care_group <> 'guide'
       RETURNING m.id, m.trip_id, m.name, m.care_group`, [req.params.mid, req.auth.companyId, careGroup ?? null, name ?? null]);
    if (!m) return bad(res, 'member not found', 404);
    broadcast(m.trip_id, 'member', m);
    res.json(m);
  }));

  app.post('/api/me/position', member, h(async (req, res) => {
    if (!isLatLng(req.body)) return bad(res, 'lat and lng are required');
    res.json(await recordPosition(req.auth.memberId, req.body, 'gps'));
  }));

  app.post('/api/me/sos', member, h(async (req, res) => {
    const { rows: [m] } = await q('SELECT id, trip_id, name FROM members WHERE id=$1', [req.auth.memberId]);
    if (isLatLng(req.body)) await recordPosition(m.id, req.body, 'gps');
    await q(`INSERT INTO alerts(trip_id, member_id, kind) VALUES ($1,$2,'sos')`, [m.trip_id, m.id]);
    await postSystemMessage({ query: q }, m.trip_id, `🆘 ${m.name} ขอความช่วยเหลือ`, { alert: 'sos', memberId: m.id });
    broadcast(m.trip_id, 'alert', { kind: 'sos', memberId: m.id, name: m.name });
    res.json({ ok: true });
  }));

  // ---------- chat ----------
  app.get('/api/trips/:id/messages', anyone, h(async (req, res) => {
    if (!(await canAccessTrip(req.auth, req.params.id))) return bad(res, 'trip not found', 404);
    const before = Number(req.query.before) || Number.MAX_SAFE_INTEGER;
    const { rows } = await q(
      `SELECT msg.*, COALESCE(s.name, m.name) AS sender_name,
              COALESCE((SELECT json_object_agg(t.lang, t.body) FROM message_translations t WHERE t.message_id=msg.id), '{}') AS translations
         FROM messages msg
         LEFT JOIN staff s ON msg.sender_kind='staff' AND s.id=msg.sender_id
         LEFT JOIN members m ON msg.sender_kind='member' AND m.id=msg.sender_id
        WHERE msg.trip_id=$1 AND msg.id < $2 ORDER BY msg.id DESC LIMIT 50`, [req.params.id, before]);
    res.json(rows.reverse());
  }));

  app.post('/api/trips/:id/messages', anyone, h(async (req, res) => {
    if (!(await canAccessTrip(req.auth, req.params.id))) return bad(res, 'trip not found', 404);
    const body = String(req.body?.body ?? '').trim().slice(0, 2000);
    if (!body) return bad(res, 'body is required');
    const kind = req.auth.kind;
    const senderId = kind === 'staff' ? req.auth.staffId : req.auth.memberId;
    const { rows: [n] } = await q(kind === 'staff' ? 'SELECT name, language FROM staff WHERE id=$1' : 'SELECT name, language FROM members WHERE id=$1', [senderId]);
    // lang = the language the sender chose in the picker (defaults to the one they read in)
    const lang = req.body?.lang ?? n?.language ?? 'th';
    if (!isLanguage(lang)) return bad(res, 'unsupported language');
    const { rows: [msg] } = await q(
      `INSERT INTO messages(trip_id, sender_kind, sender_id, body, lang) VALUES ($1,$2,$3,$4,$5) RETURNING *`,
      [req.params.id, kind, senderId, body, lang]);
    const out = { ...msg, sender_name: n?.name, translations: {} };
    broadcast(req.params.id, 'message', out);
    translateInBackground(msg);
    res.status(201).json(out);
  }));

  // ---------- cards ----------
  // Admin pre-creates codes; the card writer (ACR1252U or phone NFC) writes public_code to each chip.
  app.post('/api/cards/batch', staff, h(async (req, res) => {
    if (req.auth.role !== 'admin') return bad(res, 'admin only', 403);
    const count = Math.min(Number(req.body?.count) || 0, 500);
    const kind = req.body?.kind === 'ble' ? 'ble' : 'nfc';
    if (count < 1) return bad(res, 'count must be 1–500');
    const cards = [];
    for (let i = 0; i < count; i++) {
      const { rows: [c] } = await q(
        `INSERT INTO cards(public_code, kind, company_id) VALUES ($1,$2,$3)
         ON CONFLICT (public_code) DO NOTHING RETURNING id, public_code, kind`, [randomCode(10), kind, req.auth.companyId]);
      if (c) cards.push(c);
    }
    res.status(201).json(cards);
  }));

  // Called by the writer after writing a chip: records the chip UID (and BLE id) against the code.
  app.post('/api/cards/:code/chip', staff, h(async (req, res) => {
    const { uid, bleId } = req.body ?? {};
    if (!uid) return bad(res, 'uid is required');
    const { rows: [c] } = await q(
      `UPDATE cards SET uid=upper($3), ble_id=COALESCE(upper($4), ble_id) WHERE public_code=$1 AND company_id=$2 RETURNING id, public_code, uid, ble_id`,
      [req.params.code, req.auth.companyId, uid, bleId ?? null]).catch((e) => (e.code === '23505' ? { rows: [] } : Promise.reject(e)));
    if (!c) return bad(res, 'card not found or chip already registered', 404);
    res.json(c);
  }));

  // Bind a card to a member (screen 4 in the app). Card is found by chip UID or printed code.
  app.post('/api/cards/bind', staff, h(async (req, res) => {
    const { uid, code, memberId } = req.body ?? {};
    const { rows: [m] } = await q(
      `SELECT m.id FROM members m JOIN trips t ON t.id=m.trip_id WHERE m.id=$1 AND t.company_id=$2`, [memberId, req.auth.companyId]);
    if (!m) return bad(res, 'member not found', 404);
    const out = await tx(async (db) => {
      await db.query('UPDATE cards SET member_id=NULL WHERE member_id=$1', [memberId]);
      const { rows: [c] } = await db.query(
        `UPDATE cards SET member_id=$1 WHERE (uid=upper($2) OR public_code=$3) AND company_id=$4 AND revoked_at IS NULL
         RETURNING id, public_code, uid, kind`, [memberId, uid ?? '', code ?? '', req.auth.companyId]);
      if (c) await db.query(`UPDATE members SET device=CASE WHEN device='phone' THEN device ELSE 'tag' END WHERE id=$1`, [memberId]);
      return c;
    });
    if (!out) return bad(res, 'card not found, revoked, or from another company', 404);
    res.json(out);
  }));

  // Guide taps a card: who is this? (screen 5). Also used to check people onto the bus.
  app.post('/api/cards/scan', staff, h(async (req, res) => {
    const { uid, code, checkIn } = req.body ?? {};
    const { rows: [r] } = await q(
      `SELECT c.public_code, m.id, m.trip_id, m.name, m.care_group, m.emergency_name, m.emergency_phone, m.medical_note, m.checked_in_at
         FROM cards c JOIN members m ON m.id=c.member_id JOIN trips t ON t.id=m.trip_id
        WHERE (c.uid=upper($1) OR c.public_code=$2) AND c.revoked_at IS NULL AND t.company_id=$3`,
      [uid ?? '', code ?? '', req.auth.companyId]);
    if (!r) return bad(res, 'card is not bound to anyone in your trips', 404);
    if (checkIn) {
      await q('UPDATE members SET checked_in_at=now() WHERE id=$1', [r.id]);
      r.checked_in_at = new Date();
      broadcast(r.trip_id, 'checkin', { memberId: r.id });
    }
    res.json(r);
  }));

  app.post('/api/cards/:code/revoke', staff, h(async (req, res) => {
    const { rowCount } = await q(`UPDATE cards SET revoked_at=now(), member_id=NULL WHERE public_code=$1 AND company_id=$2`,
      [req.params.code, req.auth.companyId]);
    rowCount ? res.json({ ok: true }) : bad(res, 'card not found', 404);
  }));

  // BLE sightings from a hub or a guide phone: each seen tag takes the reporter's position.
  app.post('/api/sightings', staff, h(async (req, res) => {
    const { lat, lng, tags } = req.body ?? {};
    if (!isLatLng({ lat, lng }) || !Array.isArray(tags)) return bad(res, 'lat, lng and tags[] are required');
    const results = [];
    for (const t of tags.slice(0, 100)) {
      const { rows: [c] } = await q(
        `SELECT c.member_id FROM cards c WHERE c.ble_id=upper($1) AND c.company_id=$2 AND c.revoked_at IS NULL AND c.member_id IS NOT NULL`,
        [t.bleId ?? '', req.auth.companyId]);
      if (c) results.push({ bleId: t.bleId, ...(await recordPosition(c.member_id, { lat, lng, accuracy: 30 }, 'ble')) });
    }
    res.json(results);
  }));

  // ---------- public (anyone who finds a lost person and scans the QR) ----------
  app.get('/api/public/cards/:code', h(async (req, res) => {
    const { rows: [r] } = await q(
      `SELECT split_part(m.name,' ',1) AS first_name, m.emergency_phone, t.name AS trip_name
         FROM cards c JOIN members m ON m.id=c.member_id JOIN trips t ON t.id=m.trip_id
        WHERE c.public_code=$1 AND c.revoked_at IS NULL`, [req.params.code]);
    if (!r) return bad(res, 'card not active', 404);
    res.json(r); // deliberately no medical notes, full name or location
  }));

  app.post('/api/public/cards/:code/found', h(async (req, res) => {
    const { rows: [m] } = await q(
      `SELECT m.id, m.trip_id, m.name FROM cards c JOIN members m ON m.id=c.member_id WHERE c.public_code=$1 AND c.revoked_at IS NULL`,
      [req.params.code]);
    if (!m) return bad(res, 'card not active', 404);
    const note = String(req.body?.note ?? '').slice(0, 300);
    if (isLatLng(req.body)) await recordPosition(m.id, req.body, 'gps');
    await q(`INSERT INTO alerts(trip_id, member_id, kind) VALUES ($1,$2,'found')`, [m.trip_id, m.id]);
    await postSystemMessage({ query: q }, m.trip_id, `🙋 มีคนพบ ${m.name} และสแกนการ์ดแล้ว${note ? `: "${note}"` : ''}`, { alert: 'found', memberId: m.id });
    broadcast(m.trip_id, 'alert', { kind: 'found', memberId: m.id, name: m.name });
    res.json({ ok: true, message: 'แจ้งไกด์แล้ว ขอบคุณที่ช่วยเหลือ' });
  }));

  app.use((err, req, res, next) => {
    console.error(err);
    res.status(500).json({ error: 'internal error' });
  });
  return app;
}
