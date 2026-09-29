import { WebSocketServer } from 'ws';
import { verify } from './auth.js';

// One room per trip. Clients connect to /ws?token=<jwt>&trip=<tripId>.
const rooms = new Map();

export function attachRealtime(server, canJoin) {
  const wss = new WebSocketServer({ server, path: '/ws' });
  wss.on('connection', async (ws, req) => {
    const url = new URL(req.url, 'http://x');
    let auth;
    try {
      auth = verify(url.searchParams.get('token'));
    } catch {
      return ws.close(4401, 'unauthorized');
    }
    const tripId = url.searchParams.get('trip');
    if (!(await canJoin(auth, tripId))) return ws.close(4403, 'forbidden');
    if (!rooms.has(tripId)) rooms.set(tripId, new Set());
    rooms.get(tripId).add(ws);
    ws.on('close', () => {
      rooms.get(tripId)?.delete(ws);
      if (rooms.get(tripId)?.size === 0) rooms.delete(tripId);
    });
  });
  return wss;
}

export function broadcast(tripId, type, data) {
  const msg = JSON.stringify({ type, data });
  for (const ws of rooms.get(tripId) ?? []) if (ws.readyState === 1) ws.send(msg);
}
