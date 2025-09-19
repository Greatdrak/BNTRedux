-- Create global user admin flag and helper

-- 1) Create table to store global admin flag per auth user
CREATE TABLE IF NOT EXISTS public.user_flags (
    user_id uuid PRIMARY KEY,
    is_admin boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now()
);

-- Optional: ensure referential integrity to auth.users if available
-- Note: In Supabase hosted Postgres, the auth schema is managed by the platform.
-- Uncomment the FK if your instance allows it.
-- ALTER TABLE public.user_flags
--   ADD CONSTRAINT user_flags_user_fk
--   FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

-- 2) Helper function to check admin
CREATE OR REPLACE FUNCTION public.is_user_admin(p_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE((SELECT uf.is_admin FROM public.user_flags uf WHERE uf.user_id = p_user_id), false);
$$;

-- 3) Example: grant admin to a specific user (RUN MANUALLY with your user id)
-- INSERT INTO public.user_flags (user_id, is_admin) VALUES ('<your-user-id>', true)
--   ON CONFLICT (user_id) DO UPDATE SET is_admin = EXCLUDED.is_admin;


