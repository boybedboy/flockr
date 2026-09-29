const env = process.env;

if (!env.JWT_SECRET && env.NODE_ENV === 'production') {
  throw new Error('JWT_SECRET must be set in production');
}

export const config = {
  port: Number(env.PORT ?? 3100),
  databaseUrl: env.DATABASE_URL ?? 'postgres://flockr:flockr@localhost:5433/flockr',
  jwtSecret: env.JWT_SECRET ?? 'dev-only-secret-change-me',
  // how often the signal-lost sweep runs
  sweepMs: Number(env.SWEEP_MS ?? 15000),
};
