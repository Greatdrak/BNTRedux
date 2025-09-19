-- Mine System Implementation (Corrected)
-- Mines are deployed by players using torpedoes and only affect ships with hull level 13+

-- Create mines table
CREATE TABLE IF NOT EXISTS public.mines (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    sector_id uuid NOT NULL REFERENCES public.sectors(id) ON DELETE CASCADE,
    universe_id uuid NOT NULL REFERENCES public.universes(id) ON DELETE CASCADE,
    deployed_by uuid NOT NULL REFERENCES public.players(id) ON DELETE CASCADE,
    torpedoes_used integer DEFAULT 1,
    damage_potential integer DEFAULT 100,
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now(),
    
    CONSTRAINT mines_torpedoes_positive CHECK (torpedoes_used > 0),
    CONSTRAINT mines_damage_positive CHECK (damage_potential > 0)
);

-- Create mine hits table for tracking mine encounters
CREATE TABLE IF NOT EXISTS public.mine_hits (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    player_id uuid NOT NULL REFERENCES public.players(id) ON DELETE CASCADE,
    mine_id uuid NOT NULL REFERENCES public.mines(id) ON DELETE CASCADE,
    sector_id uuid NOT NULL REFERENCES public.sectors(id) ON DELETE CASCADE,
    universe_id uuid NOT NULL REFERENCES public.universes(id) ON DELETE CASCADE,
    damage_taken integer DEFAULT 0,
    ship_destroyed boolean DEFAULT false,
    hull_level_at_hit integer DEFAULT 0,
    hit_at timestamp with time zone DEFAULT now(),
    
    CONSTRAINT mine_hits_damage_non_negative CHECK (damage_taken >= 0),
    CONSTRAINT mine_hits_hull_level_non_negative CHECK (hull_level_at_hit >= 0)
);

-- Add indexes for performance
CREATE INDEX idx_mines_sector_id ON public.mines(sector_id);
CREATE INDEX idx_mines_universe_id ON public.mines(universe_id);
CREATE INDEX idx_mines_deployed_by ON public.mines(deployed_by);
CREATE INDEX idx_mines_active ON public.mines(is_active);
CREATE INDEX idx_mine_hits_player_id ON public.mine_hits(player_id);
CREATE INDEX idx_mine_hits_sector_id ON public.mine_hits(sector_id);
CREATE INDEX idx_mine_hits_universe_id ON public.mine_hits(universe_id);
CREATE INDEX idx_mine_hits_hit_at ON public.mine_hits(hit_at);

-- Enable RLS
ALTER TABLE public.mines ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.mine_hits ENABLE ROW LEVEL SECURITY;

-- RLS Policies for mines
CREATE POLICY "Mines are viewable by everyone" ON public.mines
    FOR SELECT USING (true);

CREATE POLICY "Players can deploy mines" ON public.mines
    FOR INSERT WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.players 
            WHERE id = deployed_by AND user_id = auth.uid()
        )
    );

CREATE POLICY "Players can remove their own mines" ON public.mines
    FOR DELETE USING (
        EXISTS (
            SELECT 1 FROM public.players 
            WHERE id = deployed_by AND user_id = auth.uid()
        )
    );

-- RLS Policies for mine_hits
CREATE POLICY "Players can view their own mine hits" ON public.mine_hits
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM public.players 
            WHERE id = player_id AND user_id = auth.uid()
        )
    );

CREATE POLICY "System can insert mine hits" ON public.mine_hits
    FOR INSERT WITH CHECK (true);

-- Function to deploy mines using torpedoes
CREATE OR REPLACE FUNCTION public.deploy_mines(
    p_player_id uuid,
    p_sector_id uuid,
    p_universe_id uuid,
    p_torpedoes_to_use integer DEFAULT 1
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_player RECORD;
    v_ship RECORD;
    v_sector RECORD;
    v_mine_id uuid;
    v_damage_potential integer;
BEGIN
    -- Get player data
    SELECT * INTO v_player
    FROM public.players
    WHERE id = p_player_id AND universe_id = p_universe_id;

    -- Get ship data
    SELECT * INTO v_ship
    FROM public.ships
    WHERE player_id = p_player_id;
    
    IF NOT FOUND THEN
        RETURN jsonb_build_object('error', 'Player or ship not found');
    END IF;
    
    -- Check if player has enough torpedoes
    IF v_ship.torpedoes < p_torpedoes_to_use THEN
        RETURN jsonb_build_object('error', 'Not enough torpedoes');
    END IF;
    
    -- Get sector info
    SELECT * INTO v_sector
    FROM public.sectors
    WHERE id = p_sector_id AND universe_id = p_universe_id;
    
    IF NOT FOUND THEN
        RETURN jsonb_build_object('error', 'Sector not found');
    END IF;
    
    -- Calculate damage potential based on torpedoes used
    v_damage_potential := p_torpedoes_to_use * 100;
    
    -- Create the mine
    INSERT INTO public.mines (
        sector_id,
        universe_id,
        deployed_by,
        torpedoes_used,
        damage_potential
    ) VALUES (
        p_sector_id,
        p_universe_id,
        p_player_id,
        p_torpedoes_to_use,
        v_damage_potential
    ) RETURNING id INTO v_mine_id;
    
    -- Remove torpedoes from ship
    UPDATE public.ships 
    SET torpedoes = torpedoes - p_torpedoes_to_use
    WHERE player_id = p_player_id;
    
    RETURN jsonb_build_object(
        'success', true,
        'mine_id', v_mine_id,
        'torpedoes_used', p_torpedoes_to_use,
        'damage_potential', v_damage_potential,
        'sector_number', v_sector.number,
        'torpedoes_remaining', v_ship.torpedoes - p_torpedoes_to_use
    );
END;
$$;

-- Function to check if player hits a mine when moving to a sector
CREATE OR REPLACE FUNCTION public.check_mine_hit(
    p_player_id uuid,
    p_sector_id uuid,
    p_universe_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_player RECORD;
    v_ship RECORD;
    v_mine RECORD;
    v_damage integer;
    v_ship_destroyed boolean := false;
    v_result jsonb;
BEGIN
    -- Get player data
    SELECT * INTO v_player
    FROM public.players
    WHERE id = p_player_id AND universe_id = p_universe_id;

    -- Get ship data
    SELECT * INTO v_ship
    FROM public.ships
    WHERE player_id = p_player_id;
    
    IF NOT FOUND THEN
        RETURN jsonb_build_object('error', 'Player or ship not found');
    END IF;
    
    -- Check if ship hull level is 13+ (vulnerable to mines)
    IF v_ship.hull_lvl < 13 THEN
        RETURN jsonb_build_object('hit', false, 'reason', 'Ship too small to trigger mines');
    END IF;
    
    -- Check if there are active mines in this sector
    SELECT * INTO v_mine
    FROM public.mines
    WHERE sector_id = p_sector_id 
      AND universe_id = p_universe_id 
      AND is_active = true
      AND deployed_by != p_player_id  -- Can't hit your own mines
    ORDER BY RANDOM()
    LIMIT 1;
    
    -- If no mines, no hit
    IF NOT FOUND THEN
        RETURN jsonb_build_object('hit', false);
    END IF;
    
    -- Calculate damage (simplified - could be more complex)
    v_damage := v_mine.damage_potential;
    
    -- Check if ship is destroyed
    IF v_damage >= v_ship.hull THEN
        v_ship_destroyed := true;
        v_damage := v_ship.hull; -- Don't over-damage
    END IF;
    
    -- Apply damage
    UPDATE public.ships 
    SET hull = hull - v_damage
    WHERE player_id = p_player_id;
    
    -- Record the mine hit
    INSERT INTO public.mine_hits (
        player_id,
        mine_id,
        sector_id,
        universe_id,
        damage_taken,
        ship_destroyed,
        hull_level_at_hit
    ) VALUES (
        p_player_id,
        v_mine.id,
        p_sector_id,
        p_universe_id,
        v_damage,
        v_ship_destroyed,
        v_ship.hull_lvl
    );
    
    -- Build result
    v_result := jsonb_build_object(
        'hit', true,
        'damage', v_damage,
        'ship_destroyed', v_ship_destroyed,
        'hull_level', v_ship.hull_lvl,
        'torpedoes_in_mine', v_mine.torpedoes_used,
        'hull_remaining', v_ship.hull - v_damage
    );
    
    RETURN v_result;
END;
$$;

-- Function to get mine information for a sector
CREATE OR REPLACE FUNCTION public.get_sector_mine_info(p_sector_id uuid, p_universe_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_mine_count integer;
    v_total_torpedoes integer;
    v_deployed_by_players jsonb;
BEGIN
    -- Count active mines and total torpedoes
    SELECT COUNT(*), SUM(torpedoes_used)
    INTO v_mine_count, v_total_torpedoes
    FROM public.mines
    WHERE sector_id = p_sector_id 
      AND universe_id = p_universe_id 
      AND is_active = true;
    
    -- Get info about who deployed mines
    SELECT jsonb_agg(
        jsonb_build_object(
            'player_handle', p.handle,
            'torpedoes_used', m.torpedoes_used,
            'deployed_at', m.created_at
        )
    )
    INTO v_deployed_by_players
    FROM public.mines m
    JOIN public.players p ON p.id = m.deployed_by
    WHERE m.sector_id = p_sector_id 
      AND m.universe_id = p_universe_id 
      AND m.is_active = true;
    
    RETURN jsonb_build_object(
        'mine_count', v_mine_count,
        'total_torpedoes', COALESCE(v_total_torpedoes, 0),
        'deployed_by', COALESCE(v_deployed_by_players, '[]'::jsonb),
        'has_mines', v_mine_count > 0
    );
END;
$$;

-- Function to remove mines (for cleanup or admin purposes)
CREATE OR REPLACE FUNCTION public.remove_mines_from_sector(
    p_sector_id uuid,
    p_universe_id uuid,
    p_player_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_removed_count integer;
BEGIN
    -- Remove mines (optionally only by specific player)
    IF p_player_id IS NOT NULL THEN
        DELETE FROM public.mines
        WHERE sector_id = p_sector_id 
          AND universe_id = p_universe_id
          AND deployed_by = p_player_id
        RETURNING id INTO v_removed_count;
    ELSE
        DELETE FROM public.mines
        WHERE sector_id = p_sector_id 
          AND universe_id = p_universe_id
        RETURNING id INTO v_removed_count;
    END IF;
    
    RETURN jsonb_build_object(
        'success', true,
        'mines_removed', v_removed_count
    );
END;
$$;

-- Grant permissions
GRANT SELECT ON public.mines TO authenticated;
GRANT SELECT ON public.mine_hits TO authenticated;
GRANT EXECUTE ON FUNCTION public.deploy_mines(uuid, uuid, uuid, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.check_mine_hit(uuid, uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_sector_mine_info(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.remove_mines_from_sector(uuid, uuid, uuid) TO authenticated;

-- Set ownership
ALTER TABLE public.mines OWNER TO postgres;
ALTER TABLE public.mine_hits OWNER TO postgres;
ALTER FUNCTION public.deploy_mines(uuid, uuid, uuid, integer) OWNER TO postgres;
ALTER FUNCTION public.check_mine_hit(uuid, uuid, uuid) OWNER TO postgres;
ALTER FUNCTION public.get_sector_mine_info(uuid, uuid) OWNER TO postgres;
ALTER FUNCTION public.remove_mines_from_sector(uuid, uuid, uuid) OWNER TO postgres;
