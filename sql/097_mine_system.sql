-- Mine System Implementation
-- Based on BNT settings: avg tech level 13 needed to hit mines safely

-- Create mines table
CREATE TABLE IF NOT EXISTS public.mines (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    sector_id uuid NOT NULL REFERENCES public.sectors(id) ON DELETE CASCADE,
    universe_id uuid NOT NULL REFERENCES public.universes(id) ON DELETE CASCADE,
    mine_type text NOT NULL DEFAULT 'standard',
    damage_potential integer DEFAULT 100,
    tech_level_required integer DEFAULT 13,
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now(),
    created_by uuid REFERENCES auth.users(id),
    
    CONSTRAINT mines_type_check CHECK (mine_type IN ('standard', 'heavy', 'plasma', 'quantum')),
    CONSTRAINT mines_damage_positive CHECK (damage_potential > 0),
    CONSTRAINT mines_tech_level_positive CHECK (tech_level_required > 0)
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
    tech_level_at_hit numeric DEFAULT 0,
    hit_at timestamp with time zone DEFAULT now(),
    
    CONSTRAINT mine_hits_damage_non_negative CHECK (damage_taken >= 0),
    CONSTRAINT mine_hits_tech_level_non_negative CHECK (tech_level_at_hit >= 0)
);

-- Add indexes for performance
CREATE INDEX idx_mines_sector_id ON public.mines(sector_id);
CREATE INDEX idx_mines_universe_id ON public.mines(universe_id);
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

CREATE POLICY "Only admins can modify mines" ON public.mines
    FOR ALL USING (
        EXISTS (
            SELECT 1 FROM public.user_profiles 
            WHERE user_id = auth.uid() AND is_admin = true
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

-- Function to calculate average tech level for a ship
CREATE OR REPLACE FUNCTION public.calculate_ship_avg_tech_level(p_player_id uuid)
RETURNS numeric
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_ship RECORD;
    v_avg_tech numeric;
BEGIN
    -- Get ship data
    SELECT 
        hull_lvl,
        engine_lvl,
        comp_lvl,
        sensor_lvl,
        shield_lvl,
        power_lvl,
        beam_lvl,
        torp_launcher_lvl,
        cloak_lvl
    INTO v_ship
    FROM public.ships
    WHERE player_id = p_player_id;
    
    IF NOT FOUND THEN
        RETURN 0;
    END IF;
    
    -- Calculate average tech level
    v_avg_tech := (
        v_ship.hull_lvl + 
        v_ship.engine_lvl + 
        v_ship.comp_lvl + 
        v_ship.sensor_lvl + 
        v_ship.shield_lvl + 
        v_ship.power_lvl + 
        v_ship.beam_lvl + 
        v_ship.torp_launcher_lvl + 
        v_ship.cloak_lvl
    ) / 9.0;
    
    RETURN v_avg_tech;
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
    v_avg_tech numeric;
    v_damage integer;
    v_ship_destroyed boolean := false;
    v_result jsonb;
BEGIN
    -- Get player and ship data
    SELECT p.*, s.* INTO v_player, v_ship
    FROM public.players p
    JOIN public.ships s ON s.player_id = p.id
    WHERE p.id = p_player_id AND p.universe_id = p_universe_id;
    
    IF NOT FOUND THEN
        RETURN jsonb_build_object('error', 'Player or ship not found');
    END IF;
    
    -- Check if there are active mines in this sector
    SELECT * INTO v_mine
    FROM public.mines
    WHERE sector_id = p_sector_id 
      AND universe_id = p_universe_id 
      AND is_active = true
    ORDER BY RANDOM()
    LIMIT 1;
    
    -- If no mines, no hit
    IF NOT FOUND THEN
        RETURN jsonb_build_object('hit', false);
    END IF;
    
    -- Calculate average tech level
    v_avg_tech := public.calculate_ship_avg_tech_level(p_player_id);
    
    -- If tech level is sufficient, avoid mine
    IF v_avg_tech >= v_mine.tech_level_required THEN
        RETURN jsonb_build_object('hit', false, 'avoided', true, 'tech_level', v_avg_tech);
    END IF;
    
    -- Calculate damage based on tech level difference
    v_damage := GREATEST(1, v_mine.damage_potential - FLOOR(v_avg_tech * 5));
    
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
        tech_level_at_hit
    ) VALUES (
        p_player_id,
        v_mine.id,
        p_sector_id,
        p_universe_id,
        v_damage,
        v_ship_destroyed,
        v_avg_tech
    );
    
    -- Build result
    v_result := jsonb_build_object(
        'hit', true,
        'damage', v_damage,
        'ship_destroyed', v_ship_destroyed,
        'tech_level', v_avg_tech,
        'tech_required', v_mine.tech_level_required,
        'mine_type', v_mine.mine_type,
        'hull_remaining', v_ship.hull - v_damage
    );
    
    RETURN v_result;
END;
$$;

-- Function to create mines in a sector (admin function)
CREATE OR REPLACE FUNCTION public.create_mines_in_sector(
    p_sector_id uuid,
    p_universe_id uuid,
    p_mine_count integer DEFAULT 1,
    p_mine_type text DEFAULT 'standard',
    p_created_by uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_mine RECORD;
    v_mines_created integer := 0;
    v_settings RECORD;
BEGIN
    -- Check if user is admin
    IF p_created_by IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM public.user_profiles 
        WHERE user_id = p_created_by AND is_admin = true
    ) THEN
        RETURN jsonb_build_object('error', 'Admin privileges required');
    END IF;
    
    -- Get universe settings for tech level requirements
    SELECT avg_tech_level_mines INTO v_settings
    FROM public.universe_settings
    WHERE universe_id = p_universe_id;
    
    -- Create mines
    FOR i IN 1..p_mine_count LOOP
        INSERT INTO public.mines (
            sector_id,
            universe_id,
            mine_type,
            damage_potential,
            tech_level_required,
            created_by
        ) VALUES (
            p_sector_id,
            p_universe_id,
            p_mine_type,
            CASE p_mine_type
                WHEN 'standard' THEN 100
                WHEN 'heavy' THEN 200
                WHEN 'plasma' THEN 300
                WHEN 'quantum' THEN 500
                ELSE 100
            END,
            COALESCE(v_settings.avg_tech_level_mines, 13),
            p_created_by
        ) RETURNING * INTO v_mine;
        
        v_mines_created := v_mines_created + 1;
    END LOOP;
    
    RETURN jsonb_build_object(
        'success', true,
        'mines_created', v_mines_created,
        'sector_id', p_sector_id
    );
END;
$$;

-- Function to get mine information for a sector (for UI display)
CREATE OR REPLACE FUNCTION public.get_sector_mine_info(p_sector_id uuid, p_universe_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_mine_count integer;
    v_mine_types jsonb;
    v_min_tech_level integer;
BEGIN
    -- Count active mines
    SELECT COUNT(*), MIN(tech_level_required)
    INTO v_mine_count, v_min_tech_level
    FROM public.mines
    WHERE sector_id = p_sector_id 
      AND universe_id = p_universe_id 
      AND is_active = true;
    
    -- Get mine types
    SELECT jsonb_agg(DISTINCT mine_type)
    INTO v_mine_types
    FROM public.mines
    WHERE sector_id = p_sector_id 
      AND universe_id = p_universe_id 
      AND is_active = true;
    
    RETURN jsonb_build_object(
        'mine_count', v_mine_count,
        'mine_types', COALESCE(v_mine_types, '[]'::jsonb),
        'min_tech_level_required', COALESCE(v_min_tech_level, 0),
        'has_mines', v_mine_count > 0
    );
END;
$$;

-- Grant permissions
GRANT SELECT ON public.mines TO authenticated;
GRANT SELECT ON public.mine_hits TO authenticated;
GRANT EXECUTE ON FUNCTION public.calculate_ship_avg_tech_level(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.check_mine_hit(uuid, uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_mines_in_sector(uuid, uuid, integer, text, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_sector_mine_info(uuid, uuid) TO authenticated;

-- Set ownership
ALTER TABLE public.mines OWNER TO postgres;
ALTER TABLE public.mine_hits OWNER TO postgres;
ALTER FUNCTION public.calculate_ship_avg_tech_level(uuid) OWNER TO postgres;
ALTER FUNCTION public.check_mine_hit(uuid, uuid, uuid) OWNER TO postgres;
ALTER FUNCTION public.create_mines_in_sector(uuid, uuid, integer, text, uuid) OWNER TO postgres;
ALTER FUNCTION public.get_sector_mine_info(uuid, uuid) OWNER TO postgres;


