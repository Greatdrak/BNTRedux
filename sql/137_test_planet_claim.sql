-- Test the planet claim function to see what error we get
-- Replace the UUIDs with actual values from your database

-- First, let's see what planets exist in sector 382
SELECT 
  p.id,
  p.name,
  p.owner_player_id,
  s.number as sector_number,
  pl.user_id,
  pl.handle
FROM planets p
JOIN sectors s ON s.id = p.sector_id
LEFT JOIN players pl ON pl.id = p.owner_player_id
WHERE s.number = 382;

-- Test the claim function (replace the UUID with your actual user_id)
-- SELECT public.game_planet_claim(
--   'your-user-id-here'::uuid,
--   382,
--   'Test Colony',
--   'your-universe-id-here'::uuid
-- );
