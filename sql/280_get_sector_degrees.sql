-- Migration: 280_get_sector_degrees.sql
-- Adds a helper function to inspect undirected warp degree per sector by universe name

CREATE OR REPLACE FUNCTION public.get_sector_degrees_by_name(p_universe_name text)
RETURNS TABLE(number integer, degree integer)
LANGUAGE sql
SECURITY DEFINER
AS $$
  WITH u AS (SELECT id FROM universes WHERE name = p_universe_name)
  SELECT s.number,
         COALESCE(
           (
             SELECT COUNT(*) FROM (
               SELECT DISTINCT CASE WHEN w.from_sector = s.id THEN w.to_sector ELSE w.from_sector END AS nbr
               FROM warps w
               WHERE w.universe_id = s.universe_id
                 AND (w.from_sector = s.id OR w.to_sector = s.id)
             ) q
           ), 0
         ) AS degree
  FROM sectors s
  WHERE s.universe_id = (SELECT id FROM u)
  ORDER BY s.number;
$$;
