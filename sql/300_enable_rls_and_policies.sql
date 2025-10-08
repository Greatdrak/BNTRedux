-- Migration: 300_enable_rls_and_policies.sql
-- Purpose: Enable RLS on sensitive public tables and add restrictive default policies

DO $$
DECLARE
  t text;
  r text;
  polname text;
BEGIN
  -- Tables flagged by the advisor
  FOR t IN SELECT unnest(ARRAY[
    'ai_action_log',
    'warps',
    'route_templates',
    'user_profiles',
    'favorites',
    'combats',
    'scans',
    'ai_players',
    'ranking_history',
    'ai_ranking_history',
    'route_waypoints',
    'route_executions',
    'route_profitability',
    'ai_player_memory',
    'ai_names',
    'bnt_capacity_lookup'
  ]) LOOP
    -- Enable RLS (idempotent)
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);

    -- Create deny-all policies for anon and authenticated if missing
    FOR r IN SELECT unnest(ARRAY['anon','authenticated']) LOOP
      polname := format('deny_all_%s', r);
      IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE schemaname = 'public' AND tablename = t AND policyname = polname
      ) THEN
        EXECUTE format(
          'CREATE POLICY %I ON public.%I FOR ALL TO %I USING (false) WITH CHECK (false)',
          polname, t, r
        );
      END IF;
    END LOOP;
  END LOOP;
END $$;

-- Note: Service role (used by server-side APIs) bypasses RLS, so app behavior is unaffected.
-- We can later add specific owner-scoped policies per table as needed for client access.
