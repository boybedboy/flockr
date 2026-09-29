import { q, tx } from './db.js';
import { evaluate, signalLost, CARE_GROUPS } from './geo.js';
import { broadcast } from './realtime.js';

const point = (p) => `SRID=4326;POINT(${Number(p.lng)} ${Number(p.lat)})`;

export async function postSystemMessage(db, tripId, body, meta) {
  const { rows } = await db.query(
    `INSERT INTO messages(trip_id, sender_kind, body, meta) VALUES ($1,'system',$2,$3) RETURNING *`,
    [tripId, body, meta],
  );
  broadcast(tripId, 'message', rows[0]);
  return rows[0];
}

async function tripCenter(db, trip) {
  if (trip.center_mode === 'fixed' && trip.fixed_lat != null) return { lat: trip.fixed_lat, lng: trip.fixed_lng };
  // follow the guide: the guide's own phone reports as a member row flagged by staff_id
  const { rows } = await db.query(
    `SELECT ST_Y(last_position::geometry) lat, ST_X(last_position::geometry) lng
       FROM members WHERE trip_id=$1 AND care_group='guide' AND last_position IS NOT NULL`,
    [trip.id],
  );
  return rows[0] ?? null;
}

/** Record a position for a member and raise/clear geofence alerts. */
export async function recordPosition(memberId, pos, source = 'gps') {
  return tx(async (db) => {
    const { rows: [m] } = await db.query(
      `UPDATE members SET last_position=$2, last_seen_at=now() WHERE id=$1 RETURNING *`,
      [memberId, point(pos)],
    );
    if (!m) return null;
    await db.query(`INSERT INTO positions(member_id, position, accuracy_m, source) VALUES ($1,$2,$3,$4)`,
      [memberId, point(pos), pos.accuracy ?? null, source]);

    const { rows: [trip] } = await db.query(
      `SELECT *, ST_Y(fixed_center::geometry) fixed_lat, ST_X(fixed_center::geometry) fixed_lng FROM trips WHERE id=$1`,
      [m.trip_id],
    );
    broadcast(trip.id, 'position', { memberId, lat: pos.lat, lng: pos.lng, source });
    if (m.care_group === 'guide') return { state: 'in' };

    const center = await tripCenter(db, trip);
    if (!center) return { state: m.fence_state };
    const prev = m.fence_state === 'lost' ? 'out' : m.fence_state;
    const r = evaluate({ center, position: pos, group: m.care_group, baseRadiusM: trip.base_radius_m, prevState: prev });

    if (r.changed || m.fence_state === 'lost') {
      await db.query(`UPDATE members SET fence_state=$2 WHERE id=$1`, [memberId, r.state]);
      const kind = r.state === 'out' ? 'out' : 'back';
      await db.query(`INSERT INTO alerts(trip_id, member_id, kind, distance_m, limit_m) VALUES ($1,$2,$3,$4,$5)`,
        [trip.id, memberId, kind, r.distanceM, r.limitM]);
      const label = CARE_GROUPS[m.care_group]?.label ?? '';
      const body = kind === 'out'
        ? `⚠ ${m.name} (${label}) ออกนอกพื้นที่ ห่าง ${r.distanceM} ม. (กำหนด ${r.limitM} ม.)`
        : `✓ ${m.name} กลับเข้าพื้นที่แล้ว`;
      await postSystemMessage(db, trip.id, body, { alert: kind, memberId, distanceM: r.distanceM, limitM: r.limitM });
      broadcast(trip.id, 'alert', { kind, memberId, name: m.name, group: m.care_group, ...r });
    }
    return r;
  });
}

/** Mark members whose device has gone quiet. Runs on a timer. */
export async function sweepSignalLost() {
  const { rows } = await q(
    `SELECT m.* FROM members m JOIN trips t ON t.id=m.trip_id
      WHERE m.care_group <> 'guide' AND m.fence_state <> 'lost' AND m.last_seen_at IS NOT NULL
        AND (t.ends_at IS NULL OR t.ends_at > now())`,
  );
  for (const m of rows) {
    if (!signalLost(m.care_group, m.last_seen_at)) continue;
    await tx(async (db) => {
      await db.query(`UPDATE members SET fence_state='lost' WHERE id=$1`, [m.id]);
      await db.query(`INSERT INTO alerts(trip_id, member_id, kind) VALUES ($1,$2,'lost')`, [m.trip_id, m.id]);
      await postSystemMessage(db, m.trip_id, `📡 สัญญาณของ ${m.name} หายไป ตำแหน่งล่าสุดอยู่บนแผนที่`, { alert: 'lost', memberId: m.id });
      broadcast(m.trip_id, 'alert', { kind: 'lost', memberId: m.id, name: m.name, group: m.care_group });
    });
  }
}
