import http from 'node:http';
import { config } from './config.js';
import { createApp, canAccessTrip } from './app.js';
import { attachRealtime } from './realtime.js';
import { migrate } from './migrate.js';
import { sweepSignalLost } from './tracking.js';

await migrate();
const server = http.createServer(createApp());
attachRealtime(server, canAccessTrip);
setInterval(() => sweepSignalLost().catch((e) => console.error('sweep', e)), config.sweepMs);
server.listen(config.port, () => console.log(`Flockr server on :${config.port}`));
