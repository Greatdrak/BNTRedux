-- Smart AI Upgrades and Cron Consolidation
--
-- 1) Remove duplicate/old AI action function signatures to fix cron error
DROP FUNCTION IF EXISTS public.run_ai_player_actions(UUID, INTEGER);
DROP FUNCTION IF EXISTS public.run_ai_player_actions(UUID);

-- 2) Recreate a single entry point used by cron and UI triggers
--    Internally performs multiple actions per AI (configurable constant)
CREATE OR REPLACE FUNCTION public.run_ai_player_actions(
  p_universe_id UUID
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  -- Tunables
  v_actions_per_ai CONSTANT INTEGER := 6;       -- number of decisions per AI per tick
  v_min_credit_reserve CONSTANT BIGINT := 5000; -- keep this much before upgrades
  v_target_fighters CONSTANT INTEGER := 50;
  v_target_torps CONSTANT INTEGER := 25;
  v_fighter_cost CONSTANT INTEGER := 100;       -- must match UI pricing used in purchase_special_port_items
  v_torp_cost CONSTANT INTEGER := 250;          -- must match UI pricing used in purchase_special_port_items

  ai RECORD;
  i INTEGER;
  v_sector_number INTEGER;
  v_result JSONB;
  v_ship RECORD;
  v_need_f INTEGER;
  v_need_t INTEGER;
  v_purchases JSONB;
BEGIN
  FOR ai IN 
    SELECT p.id AS player_id, p.user_id, COALESCE(sec.number, 0) AS sector_number
    FROM players p
    LEFT JOIN sectors sec ON sec.id = p.current_sector
    WHERE p.universe_id = p_universe_id AND p.is_ai = TRUE
  LOOP
    i := 1;
    WHILE i <= v_actions_per_ai LOOP
      -- Refresh ship snapshot
      SELECT s.* INTO v_ship FROM ships s WHERE s.player_id = ai.player_id;

      -- Step 1: Ensure at Special Port (Sector 0)
      IF COALESCE(ai.sector_number, 0) <> 0 THEN
        -- Use same RPC as UI: game_hyperspace to sector 0
        SELECT public.game_hyperspace(ai.user_id, 0)::jsonb INTO v_result;
        IF COALESCE((v_result->>'ok')::boolean, false) THEN
          PERFORM public.track_turn_spent(ai.player_id, 1, 'ai_move_special');
          -- Update current sector number locally
          ai.sector_number := 0;
        ELSE
          -- If move failed, break the loop for this AI to avoid thrashing
          EXIT;
        END IF;
      ELSE
        -- Step 2: Smart upgrade loop (prioritized)
        IF v_ship.credits > v_min_credit_reserve THEN
          -- Priority order: hull -> computer -> sensors -> engine -> shields
          -- Call the same upgrade RPC as UI (3-arg version)
          SELECT public.game_ship_upgrade(ai.user_id, 'hull', NULL)::jsonb INTO v_result;
          IF COALESCE((v_result->>'ok')::boolean, false) THEN
            PERFORM public.track_turn_spent(ai.player_id, 1, 'ai_upgrade_hull');
          ELSE
            -- try computer
            SELECT public.game_ship_upgrade(ai.user_id, 'computer', NULL)::jsonb INTO v_result;
            IF COALESCE((v_result->>'ok')::boolean, false) THEN
              PERFORM public.track_turn_spent(ai.player_id, 1, 'ai_upgrade_computer');
            ELSE
              -- sensors
              SELECT public.game_ship_upgrade(ai.user_id, 'sensors', NULL)::jsonb INTO v_result;
              IF COALESCE((v_result->>'ok')::boolean, false) THEN
                PERFORM public.track_turn_spent(ai.player_id, 1, 'ai_upgrade_sensors');
              ELSE
                -- engine
                SELECT public.game_ship_upgrade(ai.user_id, 'engine', NULL)::jsonb INTO v_result;
                IF COALESCE((v_result->>'ok')::boolean, false) THEN
                  PERFORM public.track_turn_spent(ai.player_id, 1, 'ai_upgrade_engine');
                ELSE
                  -- shields
                  SELECT public.game_ship_upgrade(ai.user_id, 'shields', NULL)::jsonb INTO v_result;
                  IF COALESCE((v_result->>'ok')::boolean, false) THEN
                    PERFORM public.track_turn_spent(ai.player_id, 1, 'ai_upgrade_shields');
                  END IF;
                END IF;
              END IF;
            END IF;
          END IF;
        END IF;

        -- Step 3: Resupply fighters/torpedoes at special port
        -- Refresh ship after upgrades
        SELECT s.* INTO v_ship FROM ships s WHERE s.player_id = ai.player_id;
        v_need_f := GREATEST(v_target_fighters - COALESCE(v_ship.fighters,0), 0);
        v_need_t := GREATEST(v_target_torps - COALESCE(v_ship.torpedoes,0), 0);

        IF v_need_f > 0 OR v_need_t > 0 THEN
          -- Build purchases JSON using same schema as UI route
          v_purchases := '[]'::jsonb;
          IF v_need_f > 0 THEN
            v_purchases := v_purchases || jsonb_build_array(jsonb_build_object(
              'type','item','name','Fighters','quantity', v_need_f, 'cost', v_fighter_cost
            ));
          END IF;
          IF v_need_t > 0 THEN
            v_purchases := v_purchases || jsonb_build_array(jsonb_build_object(
              'type','item','name','Torpedoes','quantity', v_need_t, 'cost', v_torp_cost
            ));
          END IF;

          SELECT public.purchase_special_port_items(ai.player_id, v_purchases)::jsonb INTO v_result;
          IF COALESCE((v_result->>'success')::boolean, false) THEN
            PERFORM public.track_turn_spent(ai.player_id, 1, 'ai_resupply');
          END IF;
        END IF;
      END IF;

      i := i + 1;
    END LOOP;
  END LOOP;

  RETURN json_build_object('success', true, 'message', 'AI actions executed with smart upgrades/resupply');
EXCEPTION WHEN OTHERS THEN
  RETURN json_build_object('error', 'Failed to run AI player actions: ' || SQLERRM);
END;
$$;

-- 3) Ensure the cron wrapper exists and points to the single entry
CREATE OR REPLACE FUNCTION public.cron_run_ai_actions(p_universe_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN public.run_ai_player_actions(p_universe_id);
END;
$$;

GRANT ALL ON FUNCTION public.run_ai_player_actions(UUID) TO anon;
GRANT ALL ON FUNCTION public.run_ai_player_actions(UUID) TO authenticated;
GRANT ALL ON FUNCTION public.run_ai_player_actions(UUID) TO service_role;
GRANT ALL ON FUNCTION public.cron_run_ai_actions(UUID) TO anon;
GRANT ALL ON FUNCTION public.cron_run_ai_actions(UUID) TO authenticated;
GRANT ALL ON FUNCTION public.cron_run_ai_actions(UUID) TO service_role;
