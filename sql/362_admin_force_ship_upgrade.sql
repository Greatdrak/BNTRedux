-- Admin function to force ship upgrades for AI balancing
-- Bypasses special port and credit requirements
-- Used by automated tech leveling system

CREATE OR REPLACE FUNCTION "public"."admin_force_ship_upgrade"(
  "p_player_id" "uuid", 
  "p_attr" "text", 
  "p_levels" integer DEFAULT 1
) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_ship RECORD;
  v_levels_applied INTEGER := 0;
BEGIN
  -- Validate attribute
  IF p_attr NOT IN ('engine', 'computer', 'sensors', 'shields', 'hull', 'power', 'beam', 'torp_launcher', 'armor', 'cloak') THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Invalid upgrade attribute'
    );
  END IF;

  -- Get ship
  SELECT s.* INTO v_ship FROM ships s WHERE s.player_id = p_player_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Ship not found'
    );
  END IF;

  -- Apply upgrades (no cost, no port requirement)
  FOR i IN 1..p_levels LOOP
    CASE p_attr
      WHEN 'engine' THEN 
        UPDATE ships SET engine_lvl = engine_lvl + 1 WHERE player_id = p_player_id;
      WHEN 'computer' THEN 
        UPDATE ships SET comp_lvl = comp_lvl + 1 WHERE player_id = p_player_id;
      WHEN 'sensors' THEN 
        UPDATE ships SET sensor_lvl = sensor_lvl + 1 WHERE player_id = p_player_id;
      WHEN 'shields' THEN 
        UPDATE ships SET shield_lvl = shield_lvl + 1 WHERE player_id = p_player_id;
      WHEN 'hull' THEN 
        UPDATE ships SET 
          hull_lvl = hull_lvl + 1, 
          hull = hull_max,
          cargo = FLOOR(100 * POWER(1.5, hull_lvl + 1))
        WHERE player_id = p_player_id;
      WHEN 'power' THEN 
        UPDATE ships SET power_lvl = power_lvl + 1 WHERE player_id = p_player_id;
      WHEN 'beam' THEN 
        UPDATE ships SET beam_lvl = beam_lvl + 1 WHERE player_id = p_player_id;
      WHEN 'torp_launcher' THEN 
        UPDATE ships SET torp_launcher_lvl = torp_launcher_lvl + 1 WHERE player_id = p_player_id;
      WHEN 'armor' THEN 
        UPDATE ships SET armor_lvl = armor_lvl + 1 WHERE player_id = p_player_id;
      WHEN 'cloak' THEN 
        UPDATE ships SET cloak_lvl = cloak_lvl + 1 WHERE player_id = p_player_id;
    END CASE;
    
    v_levels_applied := v_levels_applied + 1;
  END LOOP;

  -- Get updated ship data
  SELECT s.* INTO v_ship FROM ships s WHERE s.player_id = p_player_id;

  RETURN jsonb_build_object(
    'success', true,
    'attribute', p_attr,
    'levels_applied', v_levels_applied,
    'new_level', CASE p_attr
      WHEN 'engine' THEN v_ship.engine_lvl
      WHEN 'computer' THEN v_ship.comp_lvl
      WHEN 'sensors' THEN v_ship.sensor_lvl
      WHEN 'shields' THEN v_ship.shield_lvl
      WHEN 'hull' THEN v_ship.hull_lvl
      WHEN 'power' THEN v_ship.power_lvl
      WHEN 'beam' THEN v_ship.beam_lvl
      WHEN 'torp_launcher' THEN v_ship.torp_launcher_lvl
      WHEN 'armor' THEN v_ship.armor_lvl
      WHEN 'cloak' THEN v_ship.cloak_lvl
    END
  );
END;
$$;

ALTER FUNCTION "public"."admin_force_ship_upgrade"("p_player_id" "uuid", "p_attr" "text", "p_levels" integer) OWNER TO "postgres";

COMMENT ON FUNCTION "public"."admin_force_ship_upgrade"("p_player_id" "uuid", "p_attr" "text", "p_levels" integer) IS 'Admin-only function to force ship upgrades for AI balancing. Bypasses special port and credit requirements. Used by automated tech leveling system.';

-- Grant to service_role only (not to anon/authenticated)
GRANT ALL ON FUNCTION "public"."admin_force_ship_upgrade"("p_player_id" "uuid", "p_attr" "text", "p_levels" integer) TO "service_role";

