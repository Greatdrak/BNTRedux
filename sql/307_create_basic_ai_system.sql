-- Migration: 307_create_basic_ai_system.sql
-- Purpose: Create the missing AI system components

-- 1. Create ai_player_memory table if it doesn't exist
CREATE TABLE IF NOT EXISTS public.ai_player_memory (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  player_id uuid NOT NULL REFERENCES public.players(id) ON DELETE CASCADE,
  current_goal text DEFAULT 'explore',
  target_sector_id uuid REFERENCES public.sectors(id),
  last_action text,
  action_count integer DEFAULT 0,
  efficiency_score numeric DEFAULT 0.0,
  created_at timestamptz DEFAULT NOW(),
  updated_at timestamptz DEFAULT NOW()
);

-- Create unique constraint
CREATE UNIQUE INDEX IF NOT EXISTS ai_player_memory_player_id_key ON public.ai_player_memory(player_id);

-- 2. Create ai_make_decision function
CREATE OR REPLACE FUNCTION public.ai_make_decision(p_player_id uuid)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
  v_player record;
  v_ship record;
  v_sector record;
  v_planets_count int;
  v_ports_count int;
  v_credits bigint;
  v_turns int;
  v_decision text;
BEGIN
  -- Get player and ship info
  SELECT p.id, p.handle, p.current_sector, p.turns, p.is_ai, p.universe_id,
         s.credits, s.hull, s.armor, s.energy, s.fighters, s.torpedoes
  INTO v_player.id, v_player.handle, v_player.current_sector, v_player.turns, v_player.is_ai, v_player.universe_id,
       v_ship.credits, v_ship.hull, v_ship.armor, v_ship.energy, v_ship.fighters, v_ship.torpedoes
  FROM public.players p
  JOIN public.ships s ON s.player_id = p.id
  WHERE p.id = p_player_id;
  
  IF NOT FOUND THEN
    RETURN 'wait';
  END IF;
  
  -- Get sector info
  SELECT s.*, 
    (SELECT COUNT(*) FROM public.planets pl WHERE pl.sector_id = s.id AND pl.owner_player_id IS NULL) as unclaimed_planets,
    (SELECT COUNT(*) FROM public.ports pr WHERE pr.sector_id = s.id) as ports_count
  INTO v_sector
  FROM public.sectors s
  WHERE s.id = v_player.current_sector;
  
  v_credits := v_ship.credits;
  v_turns := COALESCE(v_player.turns, 0);
  
  -- Simple decision logic
  IF v_turns <= 0 THEN
    v_decision := 'wait';
  ELSIF v_sector.unclaimed_planets > 0 AND v_credits >= 1000 THEN
    v_decision := 'claim_planet';
  ELSIF v_sector.ports_count > 0 AND v_credits >= 500 THEN
    v_decision := 'trade';
  ELSIF v_ship.hull < 50 OR v_ship.armor < 10 THEN
    v_decision := 'upgrade_ship';
  ELSIF v_ship.fighters < 10 THEN
    v_decision := 'buy_fighters';
  ELSIF v_credits < 1000 THEN
    v_decision := 'trade';
  ELSE
    v_decision := 'explore';
  END IF;
  
  RETURN v_decision;
END;
$$;

-- 3. Create ai_execute_action function
CREATE OR REPLACE FUNCTION public.ai_execute_action(p_player_id uuid, p_universe_id uuid, p_action text)
RETURNS boolean
LANGUAGE plpgsql
AS $$
DECLARE
  v_result boolean := false;
  v_sector_id uuid;
  v_planet_id uuid;
  v_port_id uuid;
BEGIN
  -- Get current sector
  SELECT current_sector INTO v_sector_id
  FROM public.players
  WHERE id = p_player_id;
  
  CASE p_action
    WHEN 'claim_planet' THEN
      -- Find first unclaimed planet in current sector
      SELECT id INTO v_planet_id
      FROM public.planets
      WHERE sector_id = v_sector_id AND owner_player_id IS NULL
      LIMIT 1;
      
      IF v_planet_id IS NOT NULL THEN
        -- Call game function to claim planet
        SELECT result INTO v_result
        FROM public.game_planet_claim(p_player_id, v_planet_id, p_universe_id);
      END IF;
      
    WHEN 'trade' THEN
      -- Find first port in current sector
      SELECT id INTO v_port_id
      FROM public.ports
      WHERE sector_id = v_sector_id
      LIMIT 1;
      
      IF v_port_id IS NOT NULL THEN
        -- Simple trade: buy ore if available
        BEGIN
          SELECT result INTO v_result
          FROM public.game_trade(p_player_id, v_port_id, 'buy', 'ore', 1, p_universe_id);
        EXCEPTION WHEN OTHERS THEN
          v_result := false;
        END;
      END IF;
      
    WHEN 'upgrade_ship' THEN
      -- Upgrade hull
      BEGIN
        SELECT result INTO v_result
        FROM public.game_ship_upgrade(p_player_id, 'hull', p_universe_id);
      EXCEPTION WHEN OTHERS THEN
        v_result := false;
      END;
      
    WHEN 'buy_fighters' THEN
      -- Buy fighters at special port
      BEGIN
        SELECT id INTO v_port_id
        FROM public.ports
        WHERE sector_id = v_sector_id AND kind = 'special'
        LIMIT 1;
        
        IF v_port_id IS NOT NULL THEN
          SELECT result INTO v_result
          FROM public.purchase_special_port_items(p_player_id, v_port_id, 'fighters', 1);
        END IF;
      EXCEPTION WHEN OTHERS THEN
        v_result := false;
      END;
      
    WHEN 'explore' THEN
      -- Move to random connected sector
      BEGIN
        SELECT w.to_sector_id INTO v_sector_id
        FROM public.warps w
        WHERE w.from_sector_id = (SELECT current_sector FROM public.players WHERE id = p_player_id)
        ORDER BY RANDOM()
        LIMIT 1;
        
        IF v_sector_id IS NOT NULL THEN
          SELECT result INTO v_result
          FROM public.game_move(p_player_id, (SELECT number FROM public.sectors WHERE id = v_sector_id), p_universe_id);
        END IF;
      EXCEPTION WHEN OTHERS THEN
        v_result := false;
      END;
      
    ELSE
      v_result := false;
  END CASE;
  
  RETURN v_result;
END;
$$;

-- 4. Initialize AI memory for existing AI players
INSERT INTO public.ai_player_memory (player_id, current_goal)
SELECT p.id, 'explore'
FROM public.players p
WHERE p.is_ai = true
  AND NOT EXISTS (
    SELECT 1 FROM public.ai_player_memory m 
    WHERE m.player_id = p.id
  );
