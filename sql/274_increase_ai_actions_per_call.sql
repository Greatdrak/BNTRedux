-- Increase AI Actions Per Cron Call
--
-- Adds an overloaded function to allow multiple actions per AI per run.
-- Keeps the existing signature for backward compatibility with cron.

-- 1) Core function with actions-per-AI parameter
DROP FUNCTION IF EXISTS public.run_ai_player_actions(UUID, INTEGER);

CREATE OR REPLACE FUNCTION public.run_ai_player_actions(
  p_universe_id UUID,
  p_actions_per_ai INTEGER DEFAULT 5
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  ai_player RECORD;
  actions_taken INTEGER := 0;
  v_action_idx INTEGER;
  v_personality TEXT;
  v_port_data RECORD;
  v_planets_data RECORD;
  v_target_sector INTEGER;
  v_target_sector_id UUID;
  v_decision INTEGER;
BEGIN
  IF p_actions_per_ai IS NULL OR p_actions_per_ai < 1 THEN
    p_actions_per_ai := 1;
  ELSIF p_actions_per_ai > 20 THEN
    -- Guardrail to prevent runaway loops
    p_actions_per_ai := 20;
  END IF;

  FOR ai_player IN 
    SELECT p.id, p.handle, COALESCE(p.ai_personality::text, 'balanced') AS ai_personality,
           s.id AS ship_id, s.credits, p.current_sector AS sector_id,
           s.ore, s.organics, s.goods, s.energy, s.colonists, s.fighters, s.torpedoes,
           COALESCE(sec.number, 0) AS sector_number
    FROM public.players p
    JOIN public.ships s ON p.id = s.player_id
    LEFT JOIN public.sectors sec ON p.current_sector = sec.id
    WHERE p.universe_id = p_universe_id AND p.is_ai = TRUE
  LOOP
    v_personality := COALESCE(ai_player.ai_personality, 'balanced');

    v_action_idx := 1;
    WHILE v_action_idx <= p_actions_per_ai LOOP
      v_decision := floor(random() * 100);

      -- Trading helper (used by multiple personalities)
      PERFORM 1; -- no-op so we can keep structure tidy
      SELECT * INTO v_port_data FROM public.ports WHERE sector_id = ai_player.sector_id;

      IF v_personality = 'trader' THEN
        IF v_decision < 70 THEN
          IF FOUND THEN
            IF ai_player.credits > 2000 AND v_port_data.ore > 0 AND v_port_data.price_ore < 12 THEN
              UPDATE public.ships SET credits = credits - v_port_data.price_ore * 20, ore = ore + 20 WHERE id = ai_player.ship_id;
              PERFORM public.track_turn_spent(ai_player.id, 1, 'ai_trade');
              actions_taken := actions_taken + 1; 
            ELSIF ai_player.ore > 0 AND v_port_data.kind != 'ore' AND v_port_data.price_ore > 15 THEN
              UPDATE public.ships SET credits = credits + v_port_data.price_ore * ai_player.ore, ore = 0 WHERE id = ai_player.ship_id;
              PERFORM public.track_turn_spent(ai_player.id, 1, 'ai_trade');
              actions_taken := actions_taken + 1;
            END IF;
          END IF;
        ELSIF v_decision < 90 THEN
          v_target_sector := ai_player.sector_number + (floor(random() * 3) - 1);
          SELECT id INTO v_target_sector_id FROM public.sectors WHERE universe_id = p_universe_id AND number = v_target_sector;
          IF FOUND THEN
            UPDATE public.players SET current_sector = v_target_sector_id WHERE id = ai_player.id;
            PERFORM public.track_turn_spent(ai_player.id, 1, 'ai_move');
            actions_taken := actions_taken + 1;
          END IF;
        END IF;

      ELSIF v_personality = 'explorer' THEN
        IF v_decision < 60 THEN
          v_target_sector := ai_player.sector_number + (floor(random() * 5) - 2);
          SELECT id INTO v_target_sector_id FROM public.sectors WHERE universe_id = p_universe_id AND number = v_target_sector;
          IF FOUND THEN
            UPDATE public.players SET current_sector = v_target_sector_id WHERE id = ai_player.id;
            PERFORM public.track_turn_spent(ai_player.id, 1, 'ai_explore');
            actions_taken := actions_taken + 1;
          END IF;
        ELSIF v_decision < 90 THEN
          SELECT * INTO v_planets_data FROM public.planets WHERE sector_id = ai_player.sector_id AND owner_player_id IS NULL LIMIT 1;
          IF FOUND THEN
            UPDATE public.planets SET owner_player_id = ai_player.id WHERE id = v_planets_data.id;
            PERFORM public.track_turn_spent(ai_player.id, 1, 'ai_claim_planet');
            actions_taken := actions_taken + 1;
          END IF;
        END IF;

      ELSIF v_personality = 'warrior' THEN
        IF v_decision < 50 THEN
          -- Special port supply (fighters/torps) if present
          SELECT * INTO v_port_data FROM public.ports WHERE sector_id = ai_player.sector_id AND kind = 'special';
          IF FOUND AND ai_player.credits > 1000 THEN
            UPDATE public.ships SET credits = credits - 500, fighters = fighters + 5 WHERE id = ai_player.ship_id;
            PERFORM public.track_turn_spent(ai_player.id, 1, 'ai_combat_prep');
            actions_taken := actions_taken + 1;
          END IF;
        ELSIF v_decision < 80 THEN
          v_target_sector := ai_player.sector_number + (floor(random() * 3) - 1);
          SELECT id INTO v_target_sector_id FROM public.sectors WHERE universe_id = p_universe_id AND number = v_target_sector;
          IF FOUND THEN
            UPDATE public.players SET current_sector = v_target_sector_id WHERE id = ai_player.id;
            PERFORM public.track_turn_spent(ai_player.id, 1, 'ai_patrol');
            actions_taken := actions_taken + 1;
          END IF;
        END IF;

      ELSIF v_personality = 'colonizer' THEN
        IF v_decision < 60 THEN
          SELECT * INTO v_planets_data FROM public.planets WHERE sector_id = ai_player.sector_id AND owner_player_id IS NULL LIMIT 1;
          IF FOUND THEN
            UPDATE public.planets SET owner_player_id = ai_player.id WHERE id = v_planets_data.id;
            PERFORM public.track_turn_spent(ai_player.id, 1, 'ai_colonize');
            actions_taken := actions_taken + 1;
          END IF;
        ELSIF v_decision < 85 THEN
          v_target_sector := ai_player.sector_number + (floor(random() * 2) - 1);
          SELECT id INTO v_target_sector_id FROM public.sectors WHERE universe_id = p_universe_id AND number = v_target_sector;
          IF FOUND THEN
            UPDATE public.players SET current_sector = v_target_sector_id WHERE id = ai_player.id;
            PERFORM public.track_turn_spent(ai_player.id, 1, 'ai_colonize');
            actions_taken := actions_taken + 1;
          END IF;
        END IF;

      ELSE
        -- balanced
        IF v_decision < 30 THEN
          IF FOUND AND ai_player.credits > 1000 AND v_port_data.ore > 0 THEN
            UPDATE public.ships SET credits = credits - v_port_data.price_ore * 10, ore = ore + 10 WHERE id = ai_player.ship_id;
            PERFORM public.track_turn_spent(ai_player.id, 1, 'ai_trade');
            actions_taken := actions_taken + 1;
          END IF;
        ELSIF v_decision < 60 THEN
          v_target_sector := ai_player.sector_number + 1;
          SELECT id INTO v_target_sector_id FROM public.sectors WHERE universe_id = p_universe_id AND number = v_target_sector;
          IF FOUND THEN
            UPDATE public.players SET current_sector = v_target_sector_id WHERE id = ai_player.id;
            PERFORM public.track_turn_spent(ai_player.id, 1, 'ai_move');
            actions_taken := actions_taken + 1;
          END IF;
        ELSE
          SELECT * INTO v_planets_data FROM public.planets WHERE sector_id = ai_player.sector_id AND owner_player_id IS NULL LIMIT 1;
          IF FOUND THEN
            UPDATE public.planets SET owner_player_id = ai_player.id WHERE id = v_planets_data.id;
            PERFORM public.track_turn_spent(ai_player.id, 1, 'ai_claim_planet');
            actions_taken := actions_taken + 1;
          END IF;
        END IF;
      END IF;

      v_action_idx := v_action_idx + 1;
    END LOOP;
  END LOOP;

  RETURN json_build_object(
    'success', true,
    'actions_taken', actions_taken,
    'universe_id', p_universe_id,
    'actions_per_ai', p_actions_per_ai,
    'timestamp', now()
  );
EXCEPTION WHEN OTHERS THEN
  RETURN json_build_object('error', 'Failed to run AI player actions: ' || SQLERRM);
END;
$$;

-- 2) Back-compat wrapper (keeps cron working)
DROP FUNCTION IF EXISTS public.run_ai_player_actions(UUID);

CREATE OR REPLACE FUNCTION public.run_ai_player_actions(
  p_universe_id UUID
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN public.run_ai_player_actions(p_universe_id, 5);
END;
$$;

GRANT ALL ON FUNCTION public.run_ai_player_actions(UUID, INTEGER) TO anon;
GRANT ALL ON FUNCTION public.run_ai_player_actions(UUID, INTEGER) TO authenticated;
GRANT ALL ON FUNCTION public.run_ai_player_actions(UUID, INTEGER) TO service_role;
GRANT ALL ON FUNCTION public.run_ai_player_actions(UUID) TO anon;
GRANT ALL ON FUNCTION public.run_ai_player_actions(UUID) TO authenticated;
GRANT ALL ON FUNCTION public.run_ai_player_actions(UUID) TO service_role;
