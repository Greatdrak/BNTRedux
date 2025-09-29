-- Debug: Check how many warps are being created and why
-- Let's see what's happening step by step

-- First, let's see if there are any existing universes with warps
SELECT 
    u.name,
    u.id,
    COUNT(w.id) as warp_count
FROM universes u
LEFT JOIN warps w ON u.id = w.universe_id
GROUP BY u.id, u.name
ORDER BY u.created_at DESC
LIMIT 5;
