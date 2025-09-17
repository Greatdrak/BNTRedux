-- Assign BNT-style port kinds
-- How to apply: Run once in Supabase SQL Editor

-- Only set kind for ports where kind IS NULL
UPDATE ports p
SET kind = sub.kind
FROM (
  SELECT id,
         CASE
           WHEN rnd < 0.25 THEN 'ore'
           WHEN rnd < 0.50 THEN 'organics'
           WHEN rnd < 0.75 THEN 'goods'
           WHEN rnd < 0.95 THEN 'energy'
           ELSE 'special'
         END AS kind
  FROM (
    SELECT id, (abs(mod( ('x'||substr(md5(id::text),1,8))::bit(32)::int, 10000)) / 10000.0) AS rnd
    FROM ports
    WHERE kind IS NULL
  ) t
) sub
WHERE p.id = sub.id;

-- Normalize stocks: special ports have zero stock; commodity ports boost their own stock
UPDATE ports
SET 
  ore = CASE WHEN kind = 'special' THEN 0 ELSE ore END,
  organics = CASE WHEN kind = 'special' THEN 0 ELSE organics END,
  goods = CASE WHEN kind = 'special' THEN 0 ELSE goods END,
  energy = CASE WHEN kind = 'special' THEN 0 ELSE energy END;

UPDATE ports
SET 
  ore = GREATEST(ore, 500)
WHERE kind = 'ore';

UPDATE ports
SET 
  organics = GREATEST(organics, 500)
WHERE kind = 'organics';

UPDATE ports
SET 
  goods = GREATEST(goods, 500)
WHERE kind = 'goods';

UPDATE ports
SET 
  energy = GREATEST(energy, 500)
WHERE kind = 'energy';


