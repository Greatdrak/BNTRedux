-- Migration: 283_fix_densify_lookup.sql
-- Improve densify lookup: accept UUID or case/trim-insensitive name; add by_id wrapper.

CREATE OR REPLACE FUNCTION public.densify_universe_links_by_name(
  p_universe_name text,
  p_target_min integer DEFAULT 8,
  p_max_per_sector integer DEFAULT 15,
  p_max_attempts integer DEFAULT 200000
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_id uuid;
  v_trim text := trim(p_universe_name);
  v_uuid uuid;
BEGIN
  -- Try UUID parse first
  BEGIN
    v_uuid := v_trim::uuid;
  EXCEPTION WHEN invalid_text_representation THEN
    v_uuid := NULL;
  END;

  IF v_uuid IS NOT NULL THEN
    SELECT id INTO v_id FROM universes WHERE id = v_uuid;
  END IF;

  -- Fallback to case-insensitive name match
  IF v_id IS NULL THEN
    SELECT id INTO v_id FROM universes WHERE name ILIKE v_trim LIMIT 1;
  END IF;

  IF v_id IS NULL THEN
    RETURN jsonb_build_object('error','universe_not_found','input',p_universe_name);
  END IF;

  RETURN public.densify_universe_links(v_id, p_target_min, p_max_per_sector, p_max_attempts);
END;
$$;

-- Convenience wrapper by UUID
CREATE OR REPLACE FUNCTION public.densify_universe_links_by_id(
  p_universe_id uuid,
  p_target_min integer DEFAULT 8,
  p_max_per_sector integer DEFAULT 15,
  p_max_attempts integer DEFAULT 200000
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN public.densify_universe_links(p_universe_id, p_target_min, p_max_per_sector, p_max_attempts);
END;
$$;
