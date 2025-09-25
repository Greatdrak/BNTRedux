-- Scale down total ranking score to reduce magnitude without hard-capping semantics.
-- This keeps intermediate BIGINT math from 183_harden_rankings_overflow.sql,
-- then applies a configurable SCALE_FACTOR to the final total.

-- Recreate calculate_total_score with a scaling factor applied to v_total_big
CREATE OR REPLACE FUNCTION calculate_total_score(p_player_id UUID, p_universe_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_economic INT;
  v_territorial INT;
  v_military INT;
  v_exploration INT;
  v_total_big BIGINT;
  SCALE_FACTOR INT := 100; -- increased to further reduce extremely large totals
BEGIN
  v_economic := calculate_economic_score(p_player_id, p_universe_id);
  v_territorial := calculate_territorial_score(p_player_id, p_universe_id);
  v_military := calculate_military_score(p_player_id, p_universe_id);
  v_exploration := calculate_exploration_score(p_player_id, p_universe_id);

  -- Weighted sum using BIGINT math (percent weights x100 to avoid floats)
  -- Weights: Economic 45%, Territorial 25%, Military 20%, Exploration 10%
  v_total_big := (v_economic::BIGINT * 45)
                  + (v_territorial::BIGINT * 25)
                  + (v_military::BIGINT * 20)
                  + (v_exploration::BIGINT * 10);

  -- Convert back to percentage by dividing by 100
  v_total_big := v_total_big / 100;

  -- Apply scaling to reduce magnitude
  v_total_big := v_total_big / SCALE_FACTOR;

  RETURN json_build_object(
    'economic', v_economic,
    'territorial', v_territorial,
    'military', v_military,
    'exploration', v_exploration,
    -- No hard cap; rely on scaling. If downstream storage is INT, ensure scale is sufficient.
    'total', GREATEST(0, v_total_big)::INTEGER
  );
END;
$$;


