CREATE TABLE IF NOT EXISTS user_preferences (
    user_id           TEXT PRIMARY KEY,
    digest_frequency  TEXT CHECK (digest_frequency IN ('daily', 'weekly', 'off')) DEFAULT 'off',
    unsubscribed_at   TIMESTAMPTZ,
    last_sent_at      TIMESTAMPTZ,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_user_preferences_frequency
    ON user_preferences (digest_frequency)
    WHERE unsubscribed_at IS NULL;
