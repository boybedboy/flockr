// End-to-end check against a running server: node scripts/smoke.js [baseUrl]
import WebSocket from 'ws';

const base = process.argv[2] ?? 'http://localhost:3200';
const call = async (method, path, body, token) => {
  const r = await fetch(base + path, {
    method,
    headers: { 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  const data = await r.json();
  if (!r.ok) throw new Error(`${method} ${path} -> ${r.status} ${JSON.stringify(data)}`);
  return data;
};
const step = (s) => console.log('✔', s);
const center = { lat: 18.8048, lng: 98.9216 };
const north = (m) => ({ lat: center.lat + m / 111195, lng: center.lng });

const uid = '04' + Date.now().toString(16).toUpperCase();
const bleId = 'BLE-' + Date.now().toString(36).toUpperCase();
const email = `guide${Date.now()}@example.com`;
const { token: staff } = await call('POST', '/api/auth/signup', { company: 'ทัวร์ทดสอบ', name: 'พี่ต้น', email, password: 'password123' });
step('signup guide');
const trip = await call('POST', '/api/trips', { name: 'ทริปเชียงใหม่ 3 วัน', baseRadiusM: 300 }, staff);
step(`trip created, join code ${trip.join_code}`);
await call('POST', `/api/trips/${trip.id}/guide-position`, center, staff);

const ws = new WebSocket(`${base.replace('http', 'ws')}/ws?token=${staff}&trip=${trip.id}`);
const events = [];
ws.on('message', (m) => events.push(JSON.parse(m)));
await new Promise((r) => ws.on('open', r));
step('guide websocket connected');

const adult = await call('POST', '/api/join', { code: trip.join_code, name: 'สมศรี', birthYear: 1985, consent: true });
step(`adult joined as ${adult.member.care_group}`);
const kid = await call('POST', `/api/trips/${trip.id}/members`, { name: 'ภูมิ ใจดี', birthYear: new Date().getFullYear() - 4, emergencyPhone: '089-555-1234', consent: true }, staff);
step(`kid added as ${kid.care_group}`);

const [card] = await call('POST', '/api/cards/batch', { count: 1, kind: 'ble' }, staff);
await call('POST', `/api/cards/${card.public_code}/chip`, { uid, bleId }, staff);
await call('POST', '/api/cards/bind', { uid, memberId: kid.id }, staff);
step('card written and bound to kid');

const r1 = await call('POST', '/api/me/position', north(80), adult.token);
if (r1.state !== 'in') throw new Error('adult at 80 m should be in');
const r2 = await call('POST', '/api/sightings', { ...north(80), tags: [{ bleId }] }, staff);
if (r2[0]?.state !== 'out') throw new Error('kid at 80 m should be out: ' + JSON.stringify(r2));
step('geofence: adult in, kid out at 80 m');

const scan = await call('POST', '/api/cards/scan', { uid: uid.toLowerCase(), checkIn: true }, staff);
step(`scan -> ${scan.name}, checked in`);
const pub = await call('GET', `/api/public/cards/${card.public_code}`);
if (pub.medical_note !== undefined || pub.emergency_phone !== '089-555-1234') throw new Error('public card leaks data');
step('public QR shows only first name + emergency phone');
await call('POST', `/api/public/cards/${card.public_code}/found`, { ...north(40), note: 'อยู่หน้าร้านกาแฟ' });

await call('POST', `/api/trips/${trip.id}/messages`, { body: 'เจอกันลานจอดรถ 10:30' }, staff);
await call('POST', `/api/trips/${trip.id}/messages`, { body: 'รับทราบค่ะ' }, adult.token);
const zh = await call('POST', '/api/join', { code: trip.join_code, name: 'Li Wei', language: 'zh', consent: true });
await call('POST', `/api/trips/${trip.id}/messages`, { body: '我们在哪里集合？', lang: 'zh' }, zh.token);
const langs = await call('GET', '/api/languages');
step(`chinese tourist joined; translation ${langs.translation ? 'ON' : 'OFF (no ANTHROPIC_API_KEY)'}`);
if (langs.translation) await new Promise((r) => setTimeout(r, 8000));
const msgs = await call('GET', `/api/trips/${trip.id}/messages`, null, adult.token);
if (!msgs.every((m) => m.translations && m.lang)) throw new Error('messages missing lang/translations');
step(`chat has ${msgs.length} messages (incl. system alerts)`);
msgs.forEach((m) => console.log('   ', m.sender_kind.padEnd(6), `[${m.lang}]`, m.sender_name ?? '', m.body,
  Object.keys(m.translations).length ? JSON.stringify(m.translations) : ''));

await new Promise((r) => setTimeout(r, 300));
const alerts = events.filter((e) => e.type === 'alert').map((e) => e.data.kind);
if (!alerts.includes('out')) throw new Error('no realtime out alert');
step(`realtime alerts received: ${alerts.join(', ')}`);
ws.close();
console.log('\nALL GOOD');
