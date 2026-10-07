-- ============================================================
-- Operation Poisoned Pipeline
-- S06 - Behind the Firewall
-- Nexora production database seed (nexora_prod)
-- ============================================================

-- ------------------------------------------------------------
-- Schema: incident and component records
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS deployments (
    id              SERIAL PRIMARY KEY,
    release_name    TEXT        NOT NULL,
    build_number    INTEGER     NOT NULL,
    status          TEXT        NOT NULL,
    deployed_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS components (
    id              SERIAL PRIMARY KEY,
    slot            TEXT        NOT NULL,
    name            TEXT        NOT NULL,
    version         TEXT        NOT NULL,
    source          TEXT        NOT NULL,
    purl            TEXT        NOT NULL,
    sha256          TEXT        NOT NULL
);

CREATE TABLE IF NOT EXISTS incident_records (
    id              SERIAL PRIMARY KEY,
    incident_id     TEXT        NOT NULL UNIQUE,
    summary         TEXT        NOT NULL,
    severity        TEXT        NOT NULL,
    opened_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS ctf_final (
    id              SERIAL PRIMARY KEY,
    record_key      TEXT        NOT NULL UNIQUE,
    record_value    TEXT        NOT NULL
);

-- ------------------------------------------------------------
-- Seed: deployments
-- ------------------------------------------------------------

INSERT INTO deployments (release_name, build_number, status, deployed_at) VALUES
    ('nexora-platform-2026.09.01', 101, 'approved',     '2026-09-01T10:00:00Z'),
    ('nexora-platform-2026.09.02', 102, 'approved',     '2026-09-02T10:00:00Z'),
    ('nexora-platform-2026.09.03', 103, 'QUARANTINED',  '2026-09-03T10:00:00Z'),
    ('nexora-platform-2026.09.04', 104, 'approved',     '2026-09-04T10:00:00Z');

-- ------------------------------------------------------------
-- Seed: components (mirrors the S03 forensic evidence)
-- ------------------------------------------------------------

INSERT INTO components (slot, name, version, source, purl, sha256) VALUES
    ('lib-core',         'nexora-core',      '3.1.0', 'internal-approved-index', 'pkg:pypi/nexora-core@3.1.0',      'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90'),
    ('lib-utils',        'nexora-utils',     '2.4.1', 'upstream-unverified-index', 'pkg:pypi/nexora-utils@2.4.1',  'f0e1d2c3b4a5968778695a4b3c2d1e0ff0e1d2c3b4a5968778695a4b3c2d1e0f'),
    ('lib-platform',     'nexora-platform',  '5.0.2', 'internal-approved-index', 'pkg:pypi/nexora-platform@5.0.2',  '11223344556677889900aabbccddeeff11223344556677889900aabbccddeeff'),
    ('lib-telemetry',    'nexora-telemetry', '1.2.3', 'internal-approved-index', 'pkg:pypi/nexora-telemetry@1.2.3', 'abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789');

-- ------------------------------------------------------------
-- Seed: incident records
-- ------------------------------------------------------------

INSERT INTO incident_records (incident_id, summary, severity) VALUES
    ('INC-2026-0903-A', 'Dependency substitution detected in build 103 release channel', 'HIGH'),
    ('INC-2026-0904-B', 'Post-release forensic review opened; CI credentials rotated',    'MEDIUM');

-- ------------------------------------------------------------
-- Seed: final CTF record
-- The real S06 flag value is inserted at container start by
-- scripts/seed-postgres-s06.sh, which reads the private S06
-- environment file and passes the value as a psql parameter.
-- This keeps the flag out of the tracked SQL file entirely.
-- ------------------------------------------------------------

INSERT INTO ctf_final (record_key, record_value)
VALUES ('s06_final_record',
        'PLACEHOLDER_REPLACED_AT_STARTUP')
ON CONFLICT (record_key) DO NOTHING;

-- ------------------------------------------------------------
-- Read-only database role
-- ------------------------------------------------------------

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'ctf_reader') THEN
        CREATE ROLE ctf_reader LOGIN;
    END IF;
END
$$;

-- Password is applied by the startup seeding script so it stays
-- out of this tracked SQL file.

GRANT CONNECT ON DATABASE nexora_prod TO ctf_reader;
GRANT USAGE   ON SCHEMA public       TO ctf_reader;
GRANT SELECT  ON ALL TABLES IN SCHEMA public TO ctf_reader;

-- Ensure future tables created in this schema also default to read-only.
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO ctf_reader;
