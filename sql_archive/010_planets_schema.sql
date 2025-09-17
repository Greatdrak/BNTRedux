-- Planets Schema (Phase 1)
-- How to apply: Run this file once in Supabase SQL Editor after prior migrations.
-- Idempotent: uses CREATE TABLE IF NOT EXISTS and guards for indexes/constraints.

-- Ensure pgcrypto or uuid extension is available for gen_random_uuid
CREATE EXTENSION IF NOT EXISTS pgcrypto;

DO $$
BEGIN
    -- Create planets table (if not exists)
    CREATE TABLE IF NOT EXISTS planets (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        sector_id UUID NOT NULL REFERENCES sectors(id) ON DELETE CASCADE,
        owner_player_id UUID REFERENCES players(id) ON DELETE SET NULL,
        name TEXT NOT NULL DEFAULT 'Colony',
        ore INT DEFAULT 0,
        organics INT DEFAULT 0,
        goods INT DEFAULT 0,
        energy INT DEFAULT 0,
        hull INT DEFAULT 100,
        shield INT DEFAULT 0,
        created_at TIMESTAMPTZ DEFAULT now()
    );

    -- Unique: one planet per sector
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'planets_unique_sector'
    ) THEN
        ALTER TABLE planets
        ADD CONSTRAINT planets_unique_sector UNIQUE (sector_id);
    END IF;

    -- Indexes
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND indexname = 'idx_planets_owner'
    ) THEN
        CREATE INDEX idx_planets_owner ON planets(owner_player_id);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND indexname = 'idx_planets_sector'
    ) THEN
        CREATE INDEX idx_planets_sector ON planets(sector_id);
    END IF;
END $$;


