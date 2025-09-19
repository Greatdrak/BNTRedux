-- Cron Logs Table - Track execution of scheduled events
-- This table logs all cron heartbeat executions and individual event triggers

-- Drop existing table if it exists
DROP TABLE IF EXISTS public.cron_logs CASCADE;

-- Create cron_logs table
CREATE TABLE public.cron_logs (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    universe_id uuid NOT NULL REFERENCES public.universes(id) ON DELETE CASCADE,
    event_type text NOT NULL, -- 'heartbeat', 'turn_generation', 'port_regeneration', etc.
    event_name text NOT NULL, -- Human readable name like 'Turn Generation', 'Port Regeneration'
    status text NOT NULL, -- 'success', 'error', 'skipped'
    message text, -- Success message or error details
    execution_time_ms integer, -- How long the event took to execute
    triggered_at timestamp with time zone DEFAULT now(),
    metadata jsonb DEFAULT '{}'::jsonb -- Additional context like turns_added, ports_updated, etc.
);

-- Add indexes for performance
CREATE INDEX idx_cron_logs_universe_id ON public.cron_logs(universe_id);
CREATE INDEX idx_cron_logs_event_type ON public.cron_logs(event_type);
CREATE INDEX idx_cron_logs_triggered_at ON public.cron_logs(triggered_at DESC);
CREATE INDEX idx_cron_logs_status ON public.cron_logs(status);

-- Enable RLS
ALTER TABLE public.cron_logs ENABLE ROW LEVEL SECURITY;

-- RLS Policies
CREATE POLICY "Cron logs are viewable by everyone" ON public.cron_logs
    FOR SELECT USING (true);

CREATE POLICY "Only service role can insert cron logs" ON public.cron_logs
    FOR INSERT WITH CHECK (auth.role() = 'service_role');

-- Function to log cron events
CREATE OR REPLACE FUNCTION public.log_cron_event(
    p_universe_id uuid,
    p_event_type text,
    p_event_name text,
    p_status text,
    p_message text DEFAULT NULL,
    p_execution_time_ms integer DEFAULT NULL,
    p_metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_log_id uuid;
BEGIN
    INSERT INTO public.cron_logs (
        universe_id,
        event_type,
        event_name,
        status,
        message,
        execution_time_ms,
        metadata
    ) VALUES (
        p_universe_id,
        p_event_type,
        p_event_name,
        p_status,
        p_message,
        p_execution_time_ms,
        p_metadata
    ) RETURNING id INTO v_log_id;
    
    RETURN v_log_id;
END;
$$;

-- Function to get recent cron logs for a universe
CREATE OR REPLACE FUNCTION public.get_cron_logs(
    p_universe_id uuid,
    p_limit integer DEFAULT 50
)
RETURNS TABLE (
    id uuid,
    event_type text,
    event_name text,
    status text,
    message text,
    execution_time_ms integer,
    triggered_at timestamp with time zone,
    metadata jsonb
)
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        cl.id,
        cl.event_type,
        cl.event_name,
        cl.status,
        cl.message,
        cl.execution_time_ms,
        cl.triggered_at,
        cl.metadata
    FROM public.cron_logs cl
    WHERE cl.universe_id = p_universe_id
    ORDER BY cl.triggered_at DESC
    LIMIT p_limit;
END;
$$;

-- Function to get cron log summary (last execution times)
CREATE OR REPLACE FUNCTION public.get_cron_log_summary(p_universe_id uuid)
RETURNS TABLE (
    event_type text,
    event_name text,
    last_execution timestamp with time zone,
    last_status text,
    last_message text,
    execution_count_24h integer,
    avg_execution_time_ms numeric
)
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        cl.event_type,
        cl.event_name,
        MAX(cl.triggered_at) as last_execution,
        (SELECT cl2.status FROM public.cron_logs cl2 
         WHERE cl2.universe_id = p_universe_id AND cl2.event_type = cl.event_type 
         ORDER BY cl2.triggered_at DESC LIMIT 1) as last_status,
        (SELECT cl2.message FROM public.cron_logs cl2 
         WHERE cl2.universe_id = p_universe_id AND cl2.event_type = cl.event_type 
         ORDER BY cl2.triggered_at DESC LIMIT 1) as last_message,
        COUNT(*) FILTER (WHERE cl.triggered_at >= now() - interval '24 hours') as execution_count_24h,
        AVG(cl.execution_time_ms) FILTER (WHERE cl.execution_time_ms IS NOT NULL) as avg_execution_time_ms
    FROM public.cron_logs cl
    WHERE cl.universe_id = p_universe_id
    GROUP BY cl.event_type, cl.event_name
    ORDER BY MAX(cl.triggered_at) DESC;
END;
$$;

-- Grant permissions
GRANT SELECT ON public.cron_logs TO authenticated;
GRANT EXECUTE ON FUNCTION public.log_cron_event(uuid, text, text, text, text, integer, jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.get_cron_logs(uuid, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_cron_log_summary(uuid) TO authenticated;

-- Set ownership
ALTER TABLE public.cron_logs OWNER TO postgres;
ALTER FUNCTION public.log_cron_event(uuid, text, text, text, text, integer, jsonb) OWNER TO postgres;
ALTER FUNCTION public.get_cron_logs(uuid, integer) OWNER TO postgres;
ALTER FUNCTION public.get_cron_log_summary(uuid) OWNER TO postgres;
