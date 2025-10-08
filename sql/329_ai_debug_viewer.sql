-- View AI Debug Logs
-- This will help us see exactly what's happening with AI players

CREATE OR REPLACE FUNCTION public.view_ai_debug_logs(p_universe_id uuid, p_limit int DEFAULT 50)
RETURNS TABLE (
  log_id bigint,
  player_handle text,
  action_type text,
  action_data jsonb,
  message text,
  created_at timestamp with time zone
)
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    l.id as log_id,
    COALESCE(p.handle, 'SYSTEM') as player_handle,
    l.action_type,
    l.action_data,
    l.message,
    l.created_at
  FROM public.ai_action_log l
  LEFT JOIN public.players p ON p.id = l.player_id
  WHERE l.universe_id = p_universe_id
    AND l.action_type LIKE 'Debug:%'
  ORDER BY l.created_at DESC
  LIMIT p_limit;
END;
$$;

-- Clear old debug logs (optional)
CREATE OR REPLACE FUNCTION public.clear_ai_debug_logs(p_universe_id uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  DELETE FROM public.ai_action_log 
  WHERE universe_id = p_universe_id 
    AND action_type LIKE 'Debug:%'
    AND created_at < NOW() - INTERVAL '1 hour';
END;
$$;
