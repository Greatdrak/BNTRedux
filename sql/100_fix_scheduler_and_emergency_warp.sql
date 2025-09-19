-- Fix scheduler function return type and add missing emergency warp column
-- This addresses the errors seen in the terminal

-- First, drop the problematic function
DROP FUNCTION IF EXISTS public.get_next_scheduled_events(uuid) CASCADE;

-- Add missing column to universe_settings
ALTER TABLE public.universe_settings 
ADD COLUMN IF NOT EXISTS avg_tech_level_emergency_warp_degrades integer DEFAULT 15;

-- Update existing records to have the new column value
UPDATE public.universe_settings 
SET avg_tech_level_emergency_warp_degrades = 15 
WHERE avg_tech_level_emergency_warp_degrades IS NULL;

-- Recreate the scheduler function with correct return types
CREATE OR REPLACE FUNCTION public.get_next_scheduled_events(p_universe_id uuid)
RETURNS TABLE (
    next_turn_generation timestamp with time zone,
    next_cycle_event timestamp with time zone,
    next_update_event timestamp with time zone,
    turns_until_next_turn_generation integer,
    minutes_until_next_cycle integer,
    minutes_until_next_update integer
)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_settings RECORD;
    v_now timestamp with time zone := now();
BEGIN
    -- Get universe settings
    SELECT * INTO v_settings FROM public.universe_settings WHERE universe_id = p_universe_id;
    
    -- If no settings found, return nulls
    IF NOT FOUND THEN
        RETURN QUERY SELECT NULL::timestamp with time zone, NULL::timestamp with time zone, NULL::timestamp with time zone, NULL::integer, NULL::integer, NULL::integer;
        RETURN;
    END IF;
    
    -- Calculate next events
    RETURN QUERY
    SELECT 
        -- Next turn generation
        CASE 
            WHEN v_settings.last_turn_generation IS NULL THEN v_now
            ELSE v_settings.last_turn_generation + (v_settings.turn_generation_interval_minutes || ' minutes')::interval
        END::timestamp with time zone,
        
        -- Next cycle event
        CASE 
            WHEN v_settings.last_cycle_event IS NULL THEN v_now
            ELSE v_settings.last_cycle_event + (v_settings.cycle_interval_minutes || ' minutes')::interval
        END::timestamp with time zone,
        
        -- Next update event
        CASE 
            WHEN v_settings.last_update_event IS NULL THEN v_now
            ELSE v_settings.last_update_event + (v_settings.update_interval_minutes || ' minutes')::interval
        END::timestamp with time zone,
        
        -- Turns until next turn generation (always 0 since turns are generated immediately)
        0::integer,
        
        -- Minutes until next cycle event
        CASE 
            WHEN v_settings.last_cycle_event IS NULL THEN 0
            ELSE EXTRACT(EPOCH FROM (v_settings.last_cycle_event + (v_settings.cycle_interval_minutes || ' minutes')::interval - v_now)) / 60
        END::integer,
        
        -- Minutes until next update event
        CASE 
            WHEN v_settings.last_update_event IS NULL THEN 0
            ELSE EXTRACT(EPOCH FROM (v_settings.last_update_event + (v_settings.update_interval_minutes || ' minutes')::interval - v_now)) / 60
        END::integer;
END;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION public.get_next_scheduled_events(uuid) TO authenticated, service_role;
