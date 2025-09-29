-- Simplify capacity functions since max values are now generated columns
-- This updates get_ship_capacity to use the generated columns directly

CREATE OR REPLACE FUNCTION "public"."get_ship_capacity"("p_ship_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    ship_record RECORD;
    result JSONB;
BEGIN
    -- Get ship data including generated max columns
    SELECT 
        hull_lvl,
        hull_max,
        comp_lvl,
        armor_lvl,
        armor_max,
        power_lvl,
        energy_max,
        torp_launcher_lvl
    INTO ship_record
    FROM public.ships
    WHERE id = p_ship_id;
    
    IF NOT FOUND THEN
        RETURN jsonb_build_object('error', 'Ship not found');
    END IF;
    
    -- Use generated max columns directly (no need to calculate)
    result := jsonb_build_object(
        'hull', jsonb_build_object(
            'level', COALESCE(ship_record.hull_lvl, 1),
            'capacity', COALESCE(ship_record.hull_max, 100),
            'description', 'Cargo capacity (ore, organics, goods, energy, colonists)'
        ),
        'computer', jsonb_build_object(
            'level', COALESCE(ship_record.comp_lvl, 1),
            'capacity', public.calculate_bnt_capacity(COALESCE(ship_record.comp_lvl, 1) - 1),
            'description', 'Fighter capacity'
        ),
        'armor', jsonb_build_object(
            'level', COALESCE(ship_record.armor_lvl, 1),
            'capacity', COALESCE(ship_record.armor_max, 0),
            'description', 'Armor points capacity'
        ),
        'power', jsonb_build_object(
            'level', COALESCE(ship_record.power_lvl, 1),
            'capacity', COALESCE(ship_record.energy_max, 100),
            'description', 'Energy capacity'
        ),
        'torp_launcher', jsonb_build_object(
            'level', COALESCE(ship_record.torp_launcher_lvl, 1),
            'capacity', public.calculate_bnt_capacity(COALESCE(ship_record.torp_launcher_lvl, 1) - 1),
            'description', 'Torpedo capacity'
        )
    );
    
    RETURN result;
END;
$$;
