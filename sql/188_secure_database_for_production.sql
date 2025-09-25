-- SECURITY: Enable Row Level Security and create access policies for production deployment

-- Admin system already exists via user_profiles table

-- Enable RLS on all sensitive tables
ALTER TABLE players ENABLE ROW LEVEL SECURITY;
ALTER TABLE ships ENABLE ROW LEVEL SECURITY;
ALTER TABLE planets ENABLE ROW LEVEL SECURITY;
ALTER TABLE sectors ENABLE ROW LEVEL SECURITY;
ALTER TABLE ports ENABLE ROW LEVEL SECURITY;
ALTER TABLE trades ENABLE ROW LEVEL SECURITY;
ALTER TABLE trade_routes ENABLE ROW LEVEL SECURITY;
ALTER TABLE visited ENABLE ROW LEVEL SECURITY;
ALTER TABLE player_rankings ENABLE ROW LEVEL SECURITY;
ALTER TABLE universes ENABLE ROW LEVEL SECURITY;
ALTER TABLE universe_settings ENABLE ROW LEVEL SECURITY;

-- Players: Users can only access their own player data
CREATE POLICY "Users can view own players" ON players
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can update own players" ON players
  FOR UPDATE USING (auth.uid() = user_id);

-- Ships: Users can only access ships belonging to their players
CREATE POLICY "Users can view own ships" ON ships
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM players p 
      WHERE p.id = ships.player_id AND p.user_id = auth.uid()
    )
  );

CREATE POLICY "Users can update own ships" ON ships
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM players p 
      WHERE p.id = ships.player_id AND p.user_id = auth.uid()
    )
  );

-- Planets: Users can view all planets, but only update their own
CREATE POLICY "Users can view all planets" ON planets
  FOR SELECT USING (true);

CREATE POLICY "Users can update own planets" ON planets
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM players p 
      WHERE p.id = planets.owner_player_id AND p.user_id = auth.uid()
    )
  );

CREATE POLICY "Users can insert planets" ON planets
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM players p 
      WHERE p.id = planets.owner_player_id AND p.user_id = auth.uid()
    )
  );

-- Sectors: Users can view all sectors
CREATE POLICY "Users can view all sectors" ON sectors
  FOR SELECT USING (true);

-- Ports: Users can view all ports
CREATE POLICY "Users can view all ports" ON ports
  FOR SELECT USING (true);

-- Trades: Users can only access their own trades
CREATE POLICY "Users can view own trades" ON trades
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM players p 
      WHERE p.id = trades.player_id AND p.user_id = auth.uid()
    )
  );

CREATE POLICY "Users can insert own trades" ON trades
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM players p 
      WHERE p.id = trades.player_id AND p.user_id = auth.uid()
    )
  );

-- Trade Routes: Users can only access their own trade routes
CREATE POLICY "Users can view own trade routes" ON trade_routes
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM players p 
      WHERE p.id = trade_routes.player_id AND p.user_id = auth.uid()
    )
  );

CREATE POLICY "Users can update own trade routes" ON trade_routes
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM players p 
      WHERE p.id = trade_routes.player_id AND p.user_id = auth.uid()
    )
  );

CREATE POLICY "Users can insert own trade routes" ON trade_routes
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM players p 
      WHERE p.id = trade_routes.player_id AND p.user_id = auth.uid()
    )
  );

-- Visited: Users can only access their own visited records
CREATE POLICY "Users can view own visited" ON visited
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM players p 
      WHERE p.id = visited.player_id AND p.user_id = auth.uid()
    )
  );

CREATE POLICY "Users can insert own visited" ON visited
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM players p 
      WHERE p.id = visited.player_id AND p.user_id = auth.uid()
    )
  );

-- Player Rankings: Users can view all rankings (for leaderboard)
CREATE POLICY "Users can view all rankings" ON player_rankings
  FOR SELECT USING (true);

-- Universes: Users can view all universes
CREATE POLICY "Users can view all universes" ON universes
  FOR SELECT USING (true);

-- Universe Settings: Only admins can access
CREATE POLICY "Admins can view universe settings" ON universe_settings
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM user_profiles up 
      WHERE up.user_id = auth.uid() AND up.is_admin = true
    )
  );

CREATE POLICY "Admins can update universe settings" ON universe_settings
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM user_profiles up 
      WHERE up.user_id = auth.uid() AND up.is_admin = true
    )
  );

-- Admin check function already exists and uses user_profiles table

-- Grant necessary permissions
GRANT USAGE ON SCHEMA public TO anon, authenticated;
GRANT ALL ON ALL TABLES IN SCHEMA public TO anon, authenticated;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO anon, authenticated;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO anon, authenticated;
