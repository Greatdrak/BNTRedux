-- Fix ship capacity calculations to use proper BNT formulas and include all capacity types
-- This updates get_ship_capacity to match the authentic BNT capacity system

CREATE OR REPLACE FUNCTION "public"."get_ship_capacity"("p_ship_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    ship_record RECORD;
    result JSONB;
BEGIN
    -- Get ship data including all relevant tech levels
    SELECT 
        hull_lvl,
        comp_lvl,
        armor_lvl,
        shield_lvl,
        power_lvl,
        torp_launcher_lvl
    INTO ship_record
    FROM public.ships
    WHERE id = p_ship_id;
    
    IF NOT FOUND THEN
        RETURN jsonb_build_object('error', 'Ship not found');
    END IF;
    
    -- Calculate capacities using proper BNT formulas
    result := jsonb_build_object(
        'hull', jsonb_build_object(
            'level', COALESCE(ship_record.hull_lvl, 1),
            'capacity', public.calculate_bnt_capacity(COALESCE(ship_record.hull_lvl, 1) - 1),
            'description', 'Cargo capacity (ore, organics, goods, energy, colonists)'
        ),
        'computer', jsonb_build_object(
            'level', COALESCE(ship_record.comp_lvl, 1),
            'capacity', COALESCE(ship_record.comp_lvl, 1) * 10,  -- Fighters: comp_lvl * 10
            'description', 'Fighter capacity'
        ),
        'armor', jsonb_build_object(
            'level', COALESCE(ship_record.armor_lvl, 1),
            'capacity', public.calculate_bnt_capacity(COALESCE(ship_record.armor_lvl, 1) - 1),
            'description', 'Armor points capacity'
        ),
        'shield', jsonb_build_object(
            'level', COALESCE(ship_record.shield_lvl, 1),
            'capacity', public.calculate_bnt_capacity(COALESCE(ship_record.shield_lvl, 1) - 1),
            'description', 'Shield energy capacity'
        ),
        'power', jsonb_build_object(
            'level', COALESCE(ship_record.power_lvl, 1),
            'capacity', COALESCE(ship_record.power_lvl, 1) * 100,  -- Energy: power_lvl * 100
            'description', 'Energy capacity'
        ),
        'torp_launcher', jsonb_build_object(
            'level', COALESCE(ship_record.torp_launcher_lvl, 1),
            'capacity', COALESCE(ship_record.torp_launcher_lvl, 1) * 10,  -- Torpedoes: torp_lvl * 10
            'description', 'Torpedo capacity'
        )
    );
    
    RETURN result;
END;
$$;
