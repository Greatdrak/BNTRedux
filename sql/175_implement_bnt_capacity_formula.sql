-- Implement classic BNT formula: 100 * (1.5^tech_level) for all ship capacities
-- This replaces the current capacity system with the authentic BNT progression

-- Create a function to calculate BNT capacity
CREATE OR REPLACE FUNCTION public.calculate_bnt_capacity(tech_level INTEGER)
RETURNS BIGINT
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
    -- BNT formula: 100 * (1.5^tech_level)
    -- Round to nearest integer
    RETURN ROUND(100 * POWER(1.5, tech_level));
END;
$$;

-- Create a function to get ship capacity breakdown
CREATE OR REPLACE FUNCTION public.get_ship_capacity(p_ship_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    ship_record RECORD;
    result JSONB;
BEGIN
    -- Get ship data
    SELECT 
        hull_lvl,
        comp_lvl,
        armor_lvl,
        shield_lvl
    INTO ship_record
    FROM public.ships
    WHERE id = p_ship_id;
    
    IF NOT FOUND THEN
        RETURN jsonb_build_object('error', 'Ship not found');
    END IF;
    
    -- Calculate capacities using BNT formula
    -- Formula: 100 * (1.5^tech_level) where tech_level = hull_lvl - 1
    result := jsonb_build_object(
        'hull', jsonb_build_object(
            'level', COALESCE(ship_record.hull_lvl, 1),
            'capacity', public.calculate_bnt_capacity(COALESCE(ship_record.hull_lvl, 1) - 1),
            'description', 'Cargo capacity (ore, organics, goods, energy, colonists)'
        ),
        'computer', jsonb_build_object(
            'level', COALESCE(ship_record.comp_lvl, 1),
            'capacity', public.calculate_bnt_capacity(COALESCE(ship_record.comp_lvl, 1) - 1),
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
        )
    );
    
    RETURN result;
END;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION public.calculate_bnt_capacity(INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.calculate_bnt_capacity(INTEGER) TO service_role;
GRANT EXECUTE ON FUNCTION public.get_ship_capacity(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_ship_capacity(UUID) TO service_role;

-- Create a lookup table for quick reference (optional, for performance)
CREATE TABLE IF NOT EXISTS public.bnt_capacity_lookup (
    tech_level INTEGER PRIMARY KEY,
    capacity BIGINT NOT NULL
);

-- Populate lookup table for tech levels 0-30
INSERT INTO public.bnt_capacity_lookup (tech_level, capacity)
SELECT 
    generate_series(0, 30) as tech_level,
    public.calculate_bnt_capacity(generate_series(0, 30)) as capacity
ON CONFLICT (tech_level) DO UPDATE SET
    capacity = EXCLUDED.capacity;

-- Add comments for documentation
COMMENT ON FUNCTION public.calculate_bnt_capacity(INTEGER) IS 'Calculates ship capacity using classic BNT formula: 100 * (1.5^tech_level)';
COMMENT ON FUNCTION public.get_ship_capacity(UUID) IS 'Returns comprehensive ship capacity breakdown using BNT formula for all tech levels';
COMMENT ON TABLE public.bnt_capacity_lookup IS 'Lookup table for BNT capacity values (tech_level -> capacity)';

-- Example usage and verification
DO $$
DECLARE
    test_level INTEGER;
    test_capacity BIGINT;
BEGIN
    -- Test a few levels to verify the formula
    FOR test_level IN 0..5 LOOP
        test_capacity := public.calculate_bnt_capacity(test_level);
        RAISE NOTICE 'Tech Level %: Capacity %', test_level, test_capacity;
    END LOOP;
    
    RAISE NOTICE 'BNT Capacity formula implemented successfully!';
    RAISE NOTICE 'Formula: 100 * (1.5^tech_level)';
    RAISE NOTICE 'Lookup table populated for tech levels 0-30';
END $$;
