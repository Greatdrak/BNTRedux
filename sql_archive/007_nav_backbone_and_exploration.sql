-- Backbone warps + exploration tables + planets (stage)
-- How to apply: Run once in Supabase SQL Editor

DO $$
DECLARE
  v_universe RECORD;
  v_prev_sector UUID;
  v_curr_sector UUID;
  v_idx INT;
BEGIN
  -- For each active universe, ensure 1<->2<->...<->N backbone
  FOR v_universe IN SELECT id, sector_count FROM universes WHERE active LOOP
    v_prev_sector := NULL;
    v_idx := 1;
    WHILE v_idx <= v_universe.sector_count LOOP
      SELECT id INTO v_curr_sector FROM sectors 
      WHERE universe_id = v_universe.id AND number = v_idx;

      IF v_prev_sector IS NOT NULL THEN
        -- Insert missing directed edges prev->curr and curr->prev
        INSERT INTO warps (id, universe_id, from_sector, to_sector)
        SELECT gen_random_uuid(), v_universe.id, v_prev_sector, v_curr_sector
        WHERE NOT EXISTS (
          SELECT 1 FROM warps WHERE universe_id = v_universe.id AND from_sector = v_prev_sector AND to_sector = v_curr_sector
        );
        INSERT INTO warps (id, universe_id, from_sector, to_sector)
        SELECT gen_random_uuid(), v_universe.id, v_curr_sector, v_prev_sector
        WHERE NOT EXISTS (
          SELECT 1 FROM warps WHERE universe_id = v_universe.id AND from_sector = v_curr_sector AND to_sector = v_prev_sector
        );
      END IF;

      v_prev_sector := v_curr_sector;
      v_idx := v_idx + 1;
    END LOOP;
  END LOOP;
END $$;

-- Exploration tables
CREATE TABLE IF NOT EXISTS visited (
  player_id UUID REFERENCES players(id) ON DELETE CASCADE,
  sector_id UUID REFERENCES sectors(id) ON DELETE CASCADE,
  first_seen timestamptz DEFAULT now(),
  last_seen timestamptz DEFAULT now(),
  PRIMARY KEY(player_id, sector_id)
);

CREATE TABLE IF NOT EXISTS scans (
  player_id UUID REFERENCES players(id) ON DELETE CASCADE,
  sector_id UUID REFERENCES sectors(id) ON DELETE CASCADE,
  mode TEXT CHECK (mode IN ('single','full')),
  scanned_at timestamptz DEFAULT now(),
  PRIMARY KEY(player_id, sector_id)
);

CREATE TABLE IF NOT EXISTS favorites (
  player_id UUID REFERENCES players(id) ON DELETE CASCADE,
  sector_id UUID REFERENCES sectors(id) ON DELETE CASCADE,
  PRIMARY KEY(player_id, sector_id)
);

-- Planets (stage only)
CREATE TABLE IF NOT EXISTS planets (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  sector_id UUID REFERENCES sectors(id) ON DELETE CASCADE,
  owner_player_id UUID REFERENCES players(id) ON DELETE SET NULL,
  name TEXT,
  created_at timestamptz DEFAULT now()
);


