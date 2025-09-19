-- Global account-level admin flag (per auth user), and cleanup of prior attempts

-- 0) Cleanup: remove per-universe and prior user_flags artifacts if present
ALTER TABLE IF EXISTS public.players
  DROP COLUMN IF EXISTS is_admin;

DROP FUNCTION IF EXISTS public.is_user_admin(uuid);
DROP TABLE IF EXISTS public.user_flags;

-- 1) Create a single profile table keyed by auth user_id for global flags
CREATE TABLE IF NOT EXISTS public.user_profiles (
    user_id uuid PRIMARY KEY,
    is_admin boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now()
);

-- Optional FK to auth.users (commented; enable if your instance allows)
-- ALTER TABLE public.user_profiles
--   ADD CONSTRAINT user_profiles_user_fk
--   FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

-- 2) Helper to query admin status for any auth user
CREATE OR REPLACE FUNCTION public.is_user_admin(p_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE((SELECT up.is_admin FROM public.user_profiles up WHERE up.user_id = p_user_id), false);
$$;

-- 3) Grant yourself admin (replace with your auth user id)
-- INSERT INTO public.user_profiles (user_id, is_admin)
-- VALUES ('<your-user-id>', true)
-- ON CONFLICT (user_id) DO UPDATE SET is_admin = EXCLUDED.is_admin;


