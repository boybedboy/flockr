-- Chat translation: each person reads in their own language.
ALTER TABLE members  ADD COLUMN IF NOT EXISTS language text NOT NULL DEFAULT 'th';
ALTER TABLE staff    ADD COLUMN IF NOT EXISTS language text NOT NULL DEFAULT 'th';
ALTER TABLE messages ADD COLUMN IF NOT EXISTS lang text NOT NULL DEFAULT 'th';

CREATE TABLE IF NOT EXISTS message_translations (
  message_id  bigint NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
  lang        text NOT NULL,
  body        text NOT NULL,
  PRIMARY KEY (message_id, lang)
);

-- Monthly translated-message counter, used for plan limits and billing.
CREATE TABLE IF NOT EXISTS translation_usage (
  company_id  uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  month       date NOT NULL,
  messages    integer NOT NULL DEFAULT 0,
  PRIMARY KEY (company_id, month)
);
