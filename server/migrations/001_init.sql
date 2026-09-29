CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS companies (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name        text NOT NULL,
  plan        text NOT NULL DEFAULT 'trip',          -- trip | company
  created_at  timestamptz NOT NULL DEFAULT now()
);

-- Guides and company admins log in with email + password.
CREATE TABLE IF NOT EXISTS staff (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id    uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  email         text NOT NULL UNIQUE,
  password_hash text NOT NULL,
  name          text NOT NULL,
  role          text NOT NULL DEFAULT 'guide',       -- guide | admin
  created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS trips (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id     uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  guide_id       uuid NOT NULL REFERENCES staff(id),
  name           text NOT NULL,
  join_code      text NOT NULL UNIQUE,               -- 6 chars, shared with tourists
  base_radius_m  integer NOT NULL DEFAULT 300 CHECK (base_radius_m BETWEEN 20 AND 5000),
  -- centre follows the guide unless a fixed meeting point is set
  center_mode    text NOT NULL DEFAULT 'guide',      -- guide | fixed
  fixed_center   geography(Point, 4326),
  starts_at      timestamptz,
  ends_at        timestamptz,
  created_at     timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS members (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  trip_id          uuid NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
  name             text NOT NULL,
  care_group       text NOT NULL DEFAULT 'adult',
  birth_year       integer,
  emergency_name   text,
  emergency_phone  text,
  medical_note     text,                             -- sensitive (PDPA): explicit consent required
  consent_at       timestamptz,                      -- location + data consent
  device           text NOT NULL DEFAULT 'phone',    -- phone | tag
  fence_state      text NOT NULL DEFAULT 'in',       -- in | out | lost
  last_position    geography(Point, 4326),
  last_seen_at     timestamptz,
  checked_in_at    timestamptz,
  created_at       timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS members_trip_idx ON members(trip_id);

-- A physical card. uid = NFC chip UID; public_code = printed in the QR.
-- The chip itself stores only public_code, never personal data.
CREATE TABLE IF NOT EXISTS cards (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  uid          text UNIQUE,
  ble_id       text UNIQUE,                          -- set only on BLE cards
  public_code  text NOT NULL UNIQUE,
  kind         text NOT NULL DEFAULT 'nfc',          -- nfc | ble
  company_id   uuid REFERENCES companies(id),
  member_id    uuid UNIQUE REFERENCES members(id) ON DELETE SET NULL,
  revoked_at   timestamptz,
  created_at   timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS messages (
  id          bigserial PRIMARY KEY,
  trip_id     uuid NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
  sender_kind text NOT NULL,                         -- staff | member | system
  sender_id   uuid,
  body        text NOT NULL,
  meta        jsonb,
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS messages_trip_idx ON messages(trip_id, id DESC);

-- Raw positions, deleted by retention job 30 days after the trip ends.
CREATE TABLE IF NOT EXISTS positions (
  id          bigserial PRIMARY KEY,
  member_id   uuid NOT NULL REFERENCES members(id) ON DELETE CASCADE,
  position    geography(Point, 4326) NOT NULL,
  accuracy_m  real,
  source      text NOT NULL,                         -- gps | ble
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS positions_member_idx ON positions(member_id, created_at DESC);

CREATE TABLE IF NOT EXISTS alerts (
  id           bigserial PRIMARY KEY,
  trip_id      uuid NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
  member_id    uuid NOT NULL REFERENCES members(id) ON DELETE CASCADE,
  kind         text NOT NULL,                        -- out | back | lost | sos | found
  distance_m   integer,
  limit_m      integer,
  resolved_at  timestamptz,
  created_at   timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS schema_migrations (name text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now());
