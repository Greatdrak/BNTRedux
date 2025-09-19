-- Fix scheduler timestamp updates to handle all event types
-- The current update_scheduler_timestamp RPC only handles 3 event types,
-- but the heartbeat needs to update timestamps for all event types

-- Drop the old function
DROP FUNCTION IF EXISTS public.update_scheduler_timestamp(uuid, text, timestamp with time zone);

-- Create new function that handles all event types
CREATE OR REPLACE FUNCTION public.update_scheduler_timestamp(
    p_universe_id uuid,
    p_event_type text,
    p_timestamp timestamp with time zone DEFAULT now()
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    CASE p_event_type
        WHEN 'turn_generation' THEN
            UPDATE public.universe_settings 
            SET last_turn_generation = p_timestamp, updated_at = now()
            WHERE universe_id = p_universe_id;
        WHEN 'port_regeneration' THEN
            UPDATE public.universe_settings 
            SET last_port_regeneration_event = p_timestamp, updated_at = now()
            WHERE universe_id = p_universe_id;
        WHEN 'rankings' THEN
            UPDATE public.universe_settings 
            SET last_rankings_generation_event = p_timestamp, updated_at = now()
            WHERE universe_id = p_universe_id;
        WHEN 'defenses_check' THEN
            UPDATE public.universe_settings 
            SET last_defenses_check_event = p_timestamp, updated_at = now()
            WHERE universe_id = p_universe_id;
        WHEN 'xenobes_play' THEN
            UPDATE public.universe_settings 
            SET last_xenobes_play_event = p_timestamp, updated_at = now()
            WHERE universe_id = p_universe_id;
        WHEN 'igb_interest' THEN
            UPDATE public.universe_settings 
            SET last_igb_interest_accumulation_event = p_timestamp, updated_at = now()
            WHERE universe_id = p_universe_id;
        WHEN 'news' THEN
            UPDATE public.universe_settings 
            SET last_news_generation_event = p_timestamp, updated_at = now()
            WHERE universe_id = p_universe_id;
        WHEN 'planet_production' THEN
            UPDATE public.universe_settings 
            SET last_planet_production_event = p_timestamp, updated_at = now()
            WHERE universe_id = p_universe_id;
        WHEN 'ships_tow_fed' THEN
            UPDATE public.universe_settings 
            SET last_ships_tow_from_fed_sectors_event = p_timestamp, updated_at = now()
            WHERE universe_id = p_universe_id;
        WHEN 'sector_defenses_degrade' THEN
            UPDATE public.universe_settings 
            SET last_sector_defenses_degrade_event = p_timestamp, updated_at = now()
            WHERE universe_id = p_universe_id;
        WHEN 'apocalypse' THEN
            UPDATE public.universe_settings 
            SET last_planetary_apocalypse_event = p_timestamp, updated_at = now()
            WHERE universe_id = p_universe_id;
        WHEN 'heartbeat' THEN
            -- Heartbeat doesn't need a timestamp update, just return true
            RETURN true;
        ELSE
            -- Log unknown event type but don't fail
            RAISE WARNING 'Unknown event type: %', p_event_type;
            RETURN false;
    END CASE;
    
    RETURN true;
END;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION public.update_scheduler_timestamp(uuid, text, timestamp with time zone) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_scheduler_timestamp(uuid, text, timestamp with time zone) TO service_role;

-- Set ownership
ALTER FUNCTION public.update_scheduler_timestamp(uuid, text, timestamp with time zone) OWNER TO postgres;
