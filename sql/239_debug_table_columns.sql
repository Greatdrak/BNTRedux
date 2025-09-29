-- Debug: Check which tables have universe_id column
-- This will help us identify which table is missing the universe_id column

SELECT 
    table_name,
    column_name,
    data_type
FROM information_schema.columns 
WHERE table_schema = 'public' 
AND table_name IN (
    'trades',
    'combats', 
    'visited',
    'scans',
    'favorites',
    'planets',
    'ports',
    'ships',
    'inventories',
    'ai_player_memory',
    'player_rankings',
    'ranking_history',
    'trade_routes',
    'route_executions',
    'route_waypoints',
    'route_profitability',
    'universe_settings',
    'players',
    'warps',
    'sectors',
    'universes'
)
AND column_name = 'universe_id'
ORDER BY table_name;
