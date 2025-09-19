-- Universe Isolation Schema Fixes
-- Ensures all game objects have proper universe_id constraints to prevent cross-universe contamination

-- ============================================================================
-- CRITICAL ISSUE: Missing universe_id constraints on core tables
-- ============================================================================

-- 1. PORTS TABLE - Missing universe_id constraint
-- Ports are linked to sectors, but sectors have universe_id
-- We need to ensure ports can only be accessed within their universe

-- Add universe_id to ports table (derived from sector)
ALTER TABLE public.ports 
ADD COLUMN IF NOT EXISTS universe_id uuid;

-- Backfill universe_id from sectors
UPDATE public.ports 
SET universe_id = s.universe_id
FROM public.sectors s
WHERE ports.sector_id = s.id 
AND ports.universe_id IS NULL;

-- Add NOT NULL constraint
ALTER TABLE public.ports 
ALTER COLUMN universe_id SET NOT NULL;

-- Add foreign key constraint
ALTER TABLE public.ports 
ADD CONSTRAINT ports_universe_id_fkey 
FOREIGN KEY (universe_id) REFERENCES public.universes(id) ON DELETE CASCADE;

-- Add index for performance
CREATE INDEX IF NOT EXISTS idx_ports_universe_id ON public.ports(universe_id);

-- ============================================================================
-- 2. SHIPS TABLE - Missing universe_id constraint  
-- Ships are linked to players, but we need direct universe isolation
-- ============================================================================

-- Add universe_id to ships table (derived from player)
ALTER TABLE public.ships 
ADD COLUMN IF NOT EXISTS universe_id uuid;

-- Backfill universe_id from players
UPDATE public.ships 
SET universe_id = p.universe_id
FROM public.players p
WHERE ships.player_id = p.id 
AND ships.universe_id IS NULL;

-- Add NOT NULL constraint
ALTER TABLE public.ships 
ALTER COLUMN universe_id SET NOT NULL;

-- Add foreign key constraint
ALTER TABLE public.ships 
ADD CONSTRAINT ships_universe_id_fkey 
FOREIGN KEY (universe_id) REFERENCES public.universes(id) ON DELETE CASCADE;

-- Add index for performance
CREATE INDEX IF NOT EXISTS idx_ships_universe_id ON public.ships(universe_id);

-- ============================================================================
-- 3. INVENTORIES TABLE - Missing universe_id constraint
-- Inventories are linked to players, but we need direct universe isolation
-- ============================================================================

-- Add universe_id to inventories table (derived from player)
ALTER TABLE public.inventories 
ADD COLUMN IF NOT EXISTS universe_id uuid;

-- Backfill universe_id from players
UPDATE public.inventories 
SET universe_id = p.universe_id
FROM public.players p
WHERE inventories.player_id = p.id 
AND inventories.universe_id IS NULL;

-- Add NOT NULL constraint
ALTER TABLE public.inventories 
ALTER COLUMN universe_id SET NOT NULL;

-- Add foreign key constraint
ALTER TABLE public.inventories 
ADD CONSTRAINT inventories_universe_id_fkey 
FOREIGN KEY (universe_id) REFERENCES public.universes(id) ON DELETE CASCADE;

-- Add index for performance
CREATE INDEX IF NOT EXISTS idx_inventories_universe_id ON public.inventories(universe_id);

-- ============================================================================
-- 4. TRADES TABLE - Missing universe_id constraint
-- Trades are linked to players, but we need direct universe isolation
-- ============================================================================

-- Add universe_id to trades table (derived from player)
ALTER TABLE public.trades 
ADD COLUMN IF NOT EXISTS universe_id uuid;

-- Backfill universe_id from players
UPDATE public.trades 
SET universe_id = p.universe_id
FROM public.players p
WHERE trades.player_id = p.id 
AND trades.universe_id IS NULL;

-- Add NOT NULL constraint
ALTER TABLE public.trades 
ALTER COLUMN universe_id SET NOT NULL;

-- Add foreign key constraint
ALTER TABLE public.trades 
ADD CONSTRAINT trades_universe_id_fkey 
FOREIGN KEY (universe_id) REFERENCES public.universes(id) ON DELETE CASCADE;

-- Add index for performance
CREATE INDEX IF NOT EXISTS idx_trades_universe_id ON public.trades(universe_id);

-- ============================================================================
-- 5. TRADE_ROUTES TABLE - Missing universe_id constraint
-- Trade routes are linked to players, but we need direct universe isolation
-- ============================================================================

-- Add universe_id to trade_routes table (derived from player)
ALTER TABLE public.trade_routes 
ADD COLUMN IF NOT EXISTS universe_id uuid;

-- Backfill universe_id from players
UPDATE public.trade_routes 
SET universe_id = p.universe_id
FROM public.players p
WHERE trade_routes.player_id = p.id 
AND trade_routes.universe_id IS NULL;

-- Add NOT NULL constraint
ALTER TABLE public.trade_routes 
ALTER COLUMN universe_id SET NOT NULL;

-- Add foreign key constraint
ALTER TABLE public.trade_routes 
ADD CONSTRAINT trade_routes_universe_id_fkey 
FOREIGN KEY (universe_id) REFERENCES public.universes(id) ON DELETE CASCADE;

-- Add index for performance
CREATE INDEX IF NOT EXISTS idx_trade_routes_universe_id ON public.trade_routes(universe_id);

-- ============================================================================
-- 6. ROUTE_WAYPOINTS TABLE - Missing universe_id constraint
-- Route waypoints are linked to trade routes, but we need direct universe isolation
-- ============================================================================

-- Add universe_id to route_waypoints table (derived from trade route)
ALTER TABLE public.route_waypoints 
ADD COLUMN IF NOT EXISTS universe_id uuid;

-- Backfill universe_id from trade routes
UPDATE public.route_waypoints 
SET universe_id = tr.universe_id
FROM public.trade_routes tr
WHERE route_waypoints.route_id = tr.id 
AND route_waypoints.universe_id IS NULL;

-- Add NOT NULL constraint
ALTER TABLE public.route_waypoints 
ALTER COLUMN universe_id SET NOT NULL;

-- Add foreign key constraint
ALTER TABLE public.route_waypoints 
ADD CONSTRAINT route_waypoints_universe_id_fkey 
FOREIGN KEY (universe_id) REFERENCES public.universes(id) ON DELETE CASCADE;

-- Add index for performance
CREATE INDEX IF NOT EXISTS idx_route_waypoints_universe_id ON public.route_waypoints(universe_id);

-- ============================================================================
-- 7. PLANETS TABLE - Missing universe_id constraint
-- Planets are linked to sectors, but we need direct universe isolation
-- ============================================================================

-- Add universe_id to planets table (derived from sector)
ALTER TABLE public.planets 
ADD COLUMN IF NOT EXISTS universe_id uuid;

-- Backfill universe_id from sectors
UPDATE public.planets 
SET universe_id = s.universe_id
FROM public.sectors s
WHERE planets.sector_id = s.id 
AND planets.universe_id IS NULL;

-- Add NOT NULL constraint
ALTER TABLE public.planets 
ALTER COLUMN universe_id SET NOT NULL;

-- Add foreign key constraint
ALTER TABLE public.planets 
ADD CONSTRAINT planets_universe_id_fkey 
FOREIGN KEY (universe_id) REFERENCES public.universes(id) ON DELETE CASCADE;

-- Add index for performance
CREATE INDEX IF NOT EXISTS idx_planets_universe_id ON public.planets(universe_id);

-- ============================================================================
-- 8. RANKING_HISTORY TABLE - Already has universe_id, but ensure constraint
-- ============================================================================

-- Ensure ranking_history has proper foreign key constraint
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint 
        WHERE conname = 'ranking_history_universe_id_fkey'
    ) THEN
        ALTER TABLE public.ranking_history 
        ADD CONSTRAINT ranking_history_universe_id_fkey 
        FOREIGN KEY (universe_id) REFERENCES public.universes(id) ON DELETE CASCADE;
    END IF;
END $$;

-- ============================================================================
-- 9. CRON_LOGS TABLE - Already has universe_id, but ensure constraint
-- ============================================================================

-- Ensure cron_logs has proper foreign key constraint
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint 
        WHERE conname = 'cron_logs_universe_id_fkey'
    ) THEN
        ALTER TABLE public.cron_logs 
        ADD CONSTRAINT cron_logs_universe_id_fkey 
        FOREIGN KEY (universe_id) REFERENCES public.universes(id) ON DELETE CASCADE;
    END IF;
END $$;

-- ============================================================================
-- 10. ADD UNIVERSE ISOLATION CONSTRAINTS
-- ============================================================================

-- Add constraints to ensure universe isolation in key relationships

-- Ensure ships can only be in sectors of the same universe
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint 
        WHERE conname = 'ships_universe_sector_consistency'
    ) THEN
        ALTER TABLE public.ships 
        ADD CONSTRAINT ships_universe_sector_consistency 
        CHECK (
            EXISTS (
                SELECT 1 FROM public.players p 
                JOIN public.sectors s ON p.current_sector = s.id
                WHERE p.id = ships.player_id 
                AND s.universe_id = ships.universe_id
            )
        );
    END IF;
END $$;

-- Ensure ports can only be in sectors of the same universe
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint 
        WHERE conname = 'ports_universe_sector_consistency'
    ) THEN
        ALTER TABLE public.ports 
        ADD CONSTRAINT ports_universe_sector_consistency 
        CHECK (
            EXISTS (
                SELECT 1 FROM public.sectors s 
                WHERE s.id = ports.sector_id 
                AND s.universe_id = ports.universe_id
            )
        );
    END IF;
END $$;

-- Ensure planets can only be in sectors of the same universe
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint 
        WHERE conname = 'planets_universe_sector_consistency'
    ) THEN
        ALTER TABLE public.planets 
        ADD CONSTRAINT planets_universe_sector_consistency 
        CHECK (
            EXISTS (
                SELECT 1 FROM public.sectors s 
                WHERE s.id = planets.sector_id 
                AND s.universe_id = planets.universe_id
            )
        );
    END IF;
END $$;

-- ============================================================================
-- 11. UPDATE RPC FUNCTIONS TO ENFORCE UNIVERSE ISOLATION
-- ============================================================================

-- Update purchase_special_port_items to validate universe isolation
CREATE OR REPLACE FUNCTION public.purchase_special_port_items(
  p_player_id UUID,
  p_purchases JSONB
) RETURNS JSONB AS $$
DECLARE
  ship_record RECORD;
  player_record RECORD;
  purchase_item JSONB;
  item_type TEXT;
  item_name TEXT;
  item_quantity INTEGER;
  item_cost INTEGER;
  total_cost INTEGER := 0;
  v_result JSONB;
BEGIN
  -- Get player and ship info with universe validation
  SELECT p.*, s.*, inv.*
  INTO player_record, ship_record
  FROM players p
  JOIN ships s ON p.id = s.player_id
  JOIN inventories inv ON p.id = inv.player_id
  WHERE p.id = p_player_id;
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', jsonb_build_object('code', 'player_not_found', 'message', 'Player or ship not found'));
  END IF;
  
  -- Validate all purchases are within universe constraints
  FOR purchase_item IN SELECT * FROM jsonb_array_elements(p_purchases)
  LOOP
    item_type := purchase_item->>'type';
    item_name := purchase_item->>'name';
    item_quantity := (purchase_item->>'quantity')::integer;
    item_cost := (purchase_item->>'cost')::integer;
    
    -- Add to total cost
    total_cost := total_cost + (item_quantity * item_cost);
    
    -- Process each purchase type with universe isolation
    CASE item_type
      WHEN 'device' THEN
        -- Update ship device columns (already universe-isolated via ship)
        CASE item_name
          WHEN 'Space Beacons' THEN
            UPDATE ships SET device_space_beacons = device_space_beacons + item_quantity
            WHERE id = ship_record.id AND universe_id = player_record.universe_id;
          WHEN 'Warp Editors' THEN
            UPDATE ships SET device_warp_editors = device_warp_editors + item_quantity
            WHERE id = ship_record.id AND universe_id = player_record.universe_id;
          WHEN 'Genesis Torpedoes' THEN
            UPDATE ships SET device_genesis_torpedoes = device_genesis_torpedoes + item_quantity
            WHERE id = ship_record.id AND universe_id = player_record.universe_id;
          WHEN 'Mine Deflectors' THEN
            UPDATE ships SET device_mine_deflectors = device_mine_deflectors + item_quantity
            WHERE id = ship_record.id AND universe_id = player_record.universe_id;
          WHEN 'Emergency Warp Device' THEN
            UPDATE ships SET device_emergency_warp = true
            WHERE id = ship_record.id AND universe_id = player_record.universe_id;
          WHEN 'Escape Pod' THEN
            UPDATE ships SET device_escape_pod = true
            WHERE id = ship_record.id AND universe_id = player_record.universe_id;
          WHEN 'Fuel Scoop' THEN
            UPDATE ships SET device_fuel_scoop = true
            WHERE id = ship_record.id AND universe_id = player_record.universe_id;
          WHEN 'Last Ship Seen Device' THEN
            UPDATE ships SET device_last_seen = true
            WHERE id = ship_record.id AND universe_id = player_record.universe_id;
        END CASE;
        
      WHEN 'fighters' THEN
        UPDATE ships SET fighters = fighters + item_quantity
        WHERE id = ship_record.id AND universe_id = player_record.universe_id;
        
      WHEN 'torpedoes' THEN
        UPDATE ships SET torpedoes = torpedoes + item_quantity
        WHERE id = ship_record.id AND universe_id = player_record.universe_id;
        
      WHEN 'armor points' THEN
        UPDATE ships SET armor = armor + item_quantity
        WHERE id = ship_record.id AND universe_id = player_record.universe_id;
        
      WHEN 'colonists' THEN
        UPDATE inventories SET colonists = colonists + item_quantity
        WHERE player_id = p_player_id AND universe_id = player_record.universe_id;
        
      WHEN 'energy' THEN
        UPDATE ships SET energy = energy + item_quantity
        WHERE id = ship_record.id AND universe_id = player_record.universe_id;
    END CASE;
  END LOOP;
  
  -- Deduct credits from player (universe-isolated)
  UPDATE players 
  SET credits = credits - total_cost
  WHERE id = p_player_id AND universe_id = player_record.universe_id;
  
  RETURN jsonb_build_object(
    'success', true,
    'total_cost', total_cost,
    'remaining_credits', player_record.credits - total_cost
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- 12. ADD UNIVERSE ISOLATION INDEXES FOR PERFORMANCE
-- ============================================================================

-- Composite indexes for common universe-filtered queries
CREATE INDEX IF NOT EXISTS idx_players_universe_user ON public.players(universe_id, user_id);
CREATE INDEX IF NOT EXISTS idx_ships_universe_player ON public.ships(universe_id, player_id);
CREATE INDEX IF NOT EXISTS idx_ports_universe_sector ON public.ports(universe_id, sector_id);
CREATE INDEX IF NOT EXISTS idx_planets_universe_sector ON public.planets(universe_id, sector_id);
CREATE INDEX IF NOT EXISTS idx_trades_universe_player ON public.trades(universe_id, player_id);
CREATE INDEX IF NOT EXISTS idx_trade_routes_universe_player ON public.trade_routes(universe_id, player_id);

-- ============================================================================
-- 13. VERIFICATION QUERIES
-- ============================================================================

-- These queries can be run to verify universe isolation is working:

-- Check for any orphaned records (should return 0 rows)
-- SELECT 'ports' as table_name, COUNT(*) as orphaned_count 
-- FROM ports p 
-- LEFT JOIN sectors s ON p.sector_id = s.id 
-- WHERE p.universe_id != s.universe_id OR s.universe_id IS NULL
-- UNION ALL
-- SELECT 'ships' as table_name, COUNT(*) as orphaned_count 
-- FROM ships sh 
-- LEFT JOIN players p ON sh.player_id = p.id 
-- WHERE sh.universe_id != p.universe_id OR p.universe_id IS NULL
-- UNION ALL
-- SELECT 'inventories' as table_name, COUNT(*) as orphaned_count 
-- FROM inventories inv 
-- LEFT JOIN players p ON inv.player_id = p.id 
-- WHERE inv.universe_id != p.universe_id OR p.universe_id IS NULL;

COMMENT ON TABLE public.ports IS 'Ports table now has universe_id constraint for proper universe isolation';
COMMENT ON TABLE public.ships IS 'Ships table now has universe_id constraint for proper universe isolation';
COMMENT ON TABLE public.inventories IS 'Inventories table now has universe_id constraint for proper universe isolation';
COMMENT ON TABLE public.trades IS 'Trades table now has universe_id constraint for proper universe isolation';
COMMENT ON TABLE public.trade_routes IS 'Trade routes table now has universe_id constraint for proper universe isolation';
COMMENT ON TABLE public.route_waypoints IS 'Route waypoints table now has universe_id constraint for proper universe isolation';
COMMENT ON TABLE public.planets IS 'Planets table now has universe_id constraint for proper universe isolation';
