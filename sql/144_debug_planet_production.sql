-- Migration: Debug planet production issues
-- This migration helps debug why planet production isn't working

-- Check if there are any planets with production allocations
SELECT 
  p.id,
  p.name,
  p.colonists,
  p.production_ore_percent,
  p.production_organics_percent,
  p.production_goods_percent,
  p.production_energy_percent,
  p.production_fighters_percent,
  p.production_torpedoes_percent,
  p.last_production,
  p.last_colonist_growth,
  s.universe_id
FROM planets p
JOIN sectors s ON p.sector_id = s.id
WHERE p.owner_player_id IS NOT NULL;

-- Check universe settings for planet production
SELECT 
  u.id,
  u.name,
  us.setting_key,
  us.setting_value
FROM universes u
LEFT JOIN universe_settings us ON u.id = us.universe_id
WHERE us.setting_key IN ('planet_production_interval_minutes', 'colonist_production_rate', 'colonists_per_ore', 'colonists_per_organics', 'colonists_per_goods', 'colonists_per_energy', 'colonists_per_fighter', 'colonists_per_torpedo', 'colonists_per_credits', 'planet_interest_rate');

-- Check scheduler settings
SELECT 
  u.id,
  u.name,
  s.last_planet_production_event,
  s.planet_production_interval_minutes
FROM universes u
LEFT JOIN scheduler_settings s ON u.id = s.universe_id;

-- Test the planet production function manually
-- Replace 'your-universe-id' with an actual universe ID
-- SELECT * FROM run_planet_production('your-universe-id');
