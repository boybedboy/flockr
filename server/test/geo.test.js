import { test } from 'node:test';
import assert from 'node:assert/strict';
import { distanceM, evaluate, limitFor, groupForAge, signalLost } from '../src/geo.js';

const center = { lat: 18.8048, lng: 98.9216 }; // Doi Suthep
const north = (m) => ({ lat: center.lat + m / 111195, lng: center.lng });

test('distance is accurate to a metre over short range', () => {
  assert.ok(Math.abs(distanceM(center, north(100)) - 100) < 1);
});

test('each care group gets its share of the adult radius', () => {
  assert.equal(limitFor('adult', 300), 300);
  assert.equal(limitFor('toddler', 300), 60);
  assert.equal(limitFor('senior', 300), 150);
  assert.equal(limitFor('special', 300), 60);
});

test('age maps to a group; special is never automatic', () => {
  assert.equal(groupForAge(3), 'toddler');
  assert.equal(groupForAge(9), 'child');
  assert.equal(groupForAge(15), 'teen');
  assert.equal(groupForAge(40), 'adult');
  assert.equal(groupForAge(72), 'senior');
});

test('toddler 80 m away is out, adult is not', () => {
  const kid = evaluate({ center, position: north(80), group: 'toddler', baseRadiusM: 300 });
  const adult = evaluate({ center, position: north(80), group: 'adult', baseRadiusM: 300 });
  assert.deepEqual([kid.state, kid.changed, kid.limitM], ['out', true, 60]);
  assert.deepEqual([adult.state, adult.changed], ['in', false]);
});

test('hysteresis: must come 10% inside before counting as back', () => {
  const edge = evaluate({ center, position: north(58), group: 'toddler', baseRadiusM: 300, prevState: 'out' });
  assert.equal(edge.state, 'out');
  const back = evaluate({ center, position: north(50), group: 'toddler', baseRadiusM: 300, prevState: 'out' });
  assert.deepEqual([back.state, back.changed], ['in', true]);
});

test('signal lost is faster for special care', () => {
  const now = Date.now();
  const seen = new Date(now - 90_000);
  assert.equal(signalLost('special', seen, now), true);
  assert.equal(signalLost('adult', seen, now), false);
});
