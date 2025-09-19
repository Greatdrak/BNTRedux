-- Updated game_move function with mine system integration
-- This replaces the existing game_move function to include mine checking

CREATE OR REPLACE FUNCTION public.game_move(
    p_user_id uuid, 
    p_to_sector_number integer, 
    p_universe_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_player RECORD;
    v_current_sector RECORD;
    v_target_sector RECORD;
    v_warp_exists BOOLEAN;
    v_mine_result jsonb;
    v_result jsonb;
BEGIN
    -- Get player info - filter by universe if provided
    IF p_universe_id IS NOT NULL THEN
        SELECT p.*, s.number as current_sector_number
        INTO v_player
        FROM players p
        JOIN sectors s ON p.current_sector = s.id
        WHERE p.user_id = p_user_id AND p.universe_id = p_universe_id;
    ELSE
        SELECT p.*, s.number as current_sector_number
        INTO v_player
        FROM players p
        JOIN sectors s ON p.current_sector = s.id
        WHERE p.user_id = p_user_id;
    END IF;
    
    IF NOT FOUND THEN
        RETURN jsonb_build_object('error', jsonb_build_object('code', 'not_found', 'message', 'Player not found'));
    END IF;
    
    -- Check if player has turns
    IF v_player.turns <= 0 THEN
        RETURN jsonb_build_object('error', jsonb_build_object('code', 'no_turns', 'message', 'No turns remaining'));
    END IF;
    
    -- Get current sector info
    SELECT * INTO v_current_sector
    FROM sectors
    WHERE id = v_player.current_sector;
    
    -- Get target sector info - filter by universe if provided
    IF p_universe_id IS NOT NULL THEN
        SELECT * INTO v_target_sector
        FROM sectors
        WHERE number = p_to_sector_number AND universe_id = p_universe_id;
    ELSE
        SELECT * INTO v_target_sector
        FROM sectors
        WHERE number = p_to_sector_number;
    END IF;
    
    IF NOT FOUND THEN
        RETURN jsonb_build_object('error', jsonb_build_object('code', 'sector_not_found', 'message', 'Target sector not found'));
    END IF;
    
    -- Check if warp exists from current to target
    SELECT EXISTS(
        SELECT 1 FROM warps w
        WHERE w.from_sector = v_player.current_sector
        AND w.to_sector = v_target_sector.id
    ) INTO v_warp_exists;
    
    IF NOT v_warp_exists THEN
        RETURN jsonb_build_object('error', jsonb_build_object('code', 'no_warp', 'message', 'No warp connection to target sector'));
    END IF;
    
    -- Check for mines in target sector BEFORE moving
    v_mine_result := public.check_mine_hit(v_player.id, v_target_sector.id, v_player.universe_id);
    
    -- If mine hit occurred, handle it
    IF (v_mine_result->>'hit')::boolean THEN
        -- If ship was destroyed, don't move the player
        IF (v_mine_result->>'ship_destroyed')::boolean THEN
            -- Deduct turn but don't move
            UPDATE players 
            SET turns = turns - 1
            WHERE id = v_player.id;
            
            RETURN jsonb_build_object(
                'ok', false,
                'message', 'Ship destroyed by mine!',
                'mine_hit', v_mine_result,
                'player', jsonb_build_object(
                    'id', v_player.id,
                    'handle', v_player.handle,
                    'turns', v_player.turns - 1,
                    'current_sector', v_player.current_sector,
                    'current_sector_number', v_player.current_sector_number
                )
            );
        ELSE
            -- Ship damaged but not destroyed, continue with move
            UPDATE players 
            SET current_sector = v_target_sector.id, turns = turns - 1
            WHERE id = v_player.id;
            
            RETURN jsonb_build_object(
                'ok', true,
                'message', 'Move successful but ship damaged by mine',
                'mine_hit', v_mine_result,
                'player', jsonb_build_object(
                    'id', v_player.id,
                    'handle', v_player.handle,
                    'turns', v_player.turns - 1,
                    'current_sector', v_target_sector.id,
                    'current_sector_number', v_target_sector.number
                )
            );
        END IF;
    END IF;
    
    -- No mine hit, perform normal move
    UPDATE players 
    SET current_sector = v_target_sector.id, turns = turns - 1
    WHERE id = v_player.id;
    
    -- Return success with updated player info
    RETURN jsonb_build_object(
        'ok', true,
        'message', 'Move successful',
        'mine_hit', jsonb_build_object('hit', false),
        'player', jsonb_build_object(
            'id', v_player.id,
            'handle', v_player.handle,
            'turns', v_player.turns - 1,
            'current_sector', v_target_sector.id,
            'current_sector_number', v_target_sector.number
        )
    );
    
EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object('error', jsonb_build_object('code', 'internal_error', 'message', 'Move operation failed: ' || SQLERRM));
END;
$$;

-- Update the function ownership
ALTER FUNCTION public.game_move(uuid, integer, uuid) OWNER TO postgres;
GRANT EXECUTE ON FUNCTION public.game_move(uuid, integer, uuid) TO authenticated;


