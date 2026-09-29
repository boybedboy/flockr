// Care groups and geofence rules. Pure functions only, so they are easy to test.

// Radius of each group as a fraction of the trip's base (adult) radius.
export const CARE_GROUPS = {
  toddler: { label: 'เด็กเล็ก', ageMin: 0, ageMax: 5, factor: 0.2, notifyGuardian: true },
  child: { label: 'เด็กโต', ageMin: 6, ageMax: 12, factor: 0.4, notifyGuardian: true },
  teen: { label: 'วัยรุ่น', ageMin: 13, ageMax: 17, factor: 0.8, notifyGuardian: false },
  adult: { label: 'ผู้ใหญ่', ageMin: 18, ageMax: 59, factor: 1, notifyGuardian: false },
  senior: { label: 'ผู้สูงวัย', ageMin: 60, ageMax: 200, factor: 0.5, notifyGuardian: true },
  special: { label: 'ดูแลพิเศษ', ageMin: null, ageMax: null, factor: 0.2, notifyGuardian: true },
};

// Seconds without any position before a member of this group counts as "signal lost".
export const SIGNAL_LOST_SECONDS = { special: 60, toddler: 90, default: 300 };

export function isCareGroup(g) {
  return Object.hasOwn(CARE_GROUPS, g);
}

// Suggest a group from age; "special" is only ever chosen by a person.
export function groupForAge(age) {
  for (const [key, g] of Object.entries(CARE_GROUPS)) {
    if (g.ageMin !== null && age >= g.ageMin && age <= g.ageMax) return key;
  }
  return 'adult';
}

export function limitFor(group, baseRadiusM) {
  const g = CARE_GROUPS[group] ?? CARE_GROUPS.adult;
  return Math.round((baseRadiusM * g.factor) / 10) * 10;
}

const R_EARTH = 6371008.8;
const rad = (d) => (d * Math.PI) / 180;

// Great-circle distance in metres.
export function distanceM(a, b) {
  const dLat = rad(b.lat - a.lat);
  const dLng = rad(b.lng - a.lng);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(rad(a.lat)) * Math.cos(rad(b.lat)) * Math.sin(dLng / 2) ** 2;
  return 2 * R_EARTH * Math.asin(Math.sqrt(h));
}

// Hysteresis stops alerts flapping when someone stands right on the edge:
// you must come back 10% inside the limit before counting as "back in".
const HYSTERESIS = 0.9;

/**
 * Decide the geofence state of one member.
 * @returns {{ state: 'in'|'out', distanceM: number, limitM: number, changed: boolean }}
 */
export function evaluate({ center, position, group, baseRadiusM, prevState = 'in' }) {
  const d = distanceM(center, position);
  const limit = limitFor(group, baseRadiusM);
  let state = prevState;
  if (prevState === 'in' && d > limit) state = 'out';
  else if (prevState === 'out' && d <= limit * HYSTERESIS) state = 'in';
  return { state, distanceM: Math.round(d), limitM: limit, changed: state !== prevState };
}

export function signalLost(group, lastSeenAt, now = Date.now()) {
  if (!lastSeenAt) return false;
  const limit = SIGNAL_LOST_SECONDS[group] ?? SIGNAL_LOST_SECONDS.default;
  return (now - new Date(lastSeenAt).getTime()) / 1000 > limit;
}
