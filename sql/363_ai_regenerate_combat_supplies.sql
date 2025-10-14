-- Auto-regenerate AI combat supplies over time
-- Runs every cron cycle to slowly refill fighters/torpedoes/armor for AI players

CREATE OR REPLACE FUNCTION "public"."ai_regenerate_combat_supplies"(
  "p_universe_id" "uuid"
) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_ai_player RECORD;
  v_ship RECORD;
  v_fighter_capacity INTEGER;
  v_torpedo_capacity INTEGER;
  v_armor_capacity INTEGER;
  v_fighters_to_add INTEGER;
  v_torpedoes_to_add INTEGER;
  v_armor_to_add INTEGER;
  v_total_regenerated INTEGER := 0;
BEGIN
  -- Get all AI players in the universe
  FOR v_ai_player IN 
    SELECT p.id, p.handle
    FROM players p
    WHERE p.universe_id = p_universe_id 
    AND p.is_ai = true
  LOOP
    -- Get ship data
    SELECT s.* INTO v_ship 
    FROM ships s 
    WHERE s.player_id = v_ai_player.id;
    
    IF FOUND THEN
      -- Calculate capacities
      v_fighter_capacity := FLOOR(100 * POWER(1.5, (v_ship.comp_lvl - 1)));
      v_torpedo_capacity := v_ship.torp_launcher_lvl * 100;
      v_armor_capacity := FLOOR(100 * POWER(1.5, v_ship.armor_lvl));
      
      -- Calculate regeneration amounts (5% of capacity per cycle)
      v_fighters_to_add := FLOOR(v_fighter_capacity * 0.05);
      v_torpedoes_to_add := FLOOR(v_torpedo_capacity * 0.05);
      v_armor_to_add := FLOOR(v_armor_capacity * 0.05);
      
      -- Only regenerate if below 90% capacity
      IF (v_ship.fighters < (v_fighter_capacity * 0.9)) THEN
        v_fighters_to_add := LEAST(v_fighters_to_add, v_fighter_capacity - v_ship.fighters);
      ELSE
        v_fighters_to_add := 0;
      END IF;
      
      IF (v_ship.torpedoes < (v_torpedo_capacity * 0.9)) THEN
        v_torpedoes_to_add := LEAST(v_torpedoes_to_add, v_torpedo_capacity - v_ship.torpedoes);
      ELSE
        v_torpedoes_to_add := 0;
      END IF;
      
      IF (v_ship.armor < (v_armor_capacity * 0.9)) THEN
        v_armor_to_add := LEAST(v_armor_to_add, v_armor_capacity - v_ship.armor);
      ELSE
        v_armor_to_add := 0;
      END IF;
      
      -- Apply regeneration
      IF (v_fighters_to_add > 0 OR v_torpedoes_to_add > 0 OR v_armor_to_add > 0) THEN
        UPDATE ships 
        SET 
          fighters = LEAST(fighters + v_fighters_to_add, v_fighter_capacity),
          torpedoes = LEAST(torpedoes + v_torpedoes_to_add, v_torpedo_capacity),
          armor = LEAST(armor + v_armor_to_add, v_armor_capacity)
        WHERE player_id = v_ai_player.id;
        
        v_total_regenerated := v_total_regenerated + v_fighters_to_add + v_torpedoes_to_add + v_armor_to_add;
      END IF;
    END IF;
  END LOOP;
  
  RETURN jsonb_build_object(
    'success', true,
    'message', 'AI combat supplies regenerated',
    'total_items_regenerated', v_total_regenerated,
    'universe_id', p_universe_id
  );
END;
$$;

ALTER FUNCTION "public"."ai_regenerate_combat_supplies"("p_universe_id" "uuid") OWNER TO "postgres";

COMMENT ON FUNCTION "public"."ai_regenerate_combat_supplies"("p_universe_id" "uuid") IS 'Automatically regenerates AI combat supplies (fighters/torpedoes/armor) over time. Runs every cron cycle to slowly refill supplies.';

-- Grant to service_role only
GRANT ALL ON FUNCTION "public"."ai_regenerate_combat_supplies"("p_universe_id" "uuid") TO "service_role";
