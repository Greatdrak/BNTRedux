-- WARNING: This schema is for context only and is not meant to be run.
-- Table order and constraints may not be valid for execution.

CREATE TABLE public.ai_players (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  universe_id uuid,
  name text NOT NULL,
  ai_type text DEFAULT 'balanced'::text CHECK (ai_type = ANY (ARRAY['trader'::text, 'explorer'::text, 'military'::text, 'balanced'::text])),
  economic_score integer DEFAULT 0,
  territorial_score integer DEFAULT 0,
  military_score integer DEFAULT 0,
  exploration_score integer DEFAULT 0,
  total_score integer DEFAULT 0,
  rank_position integer,
  last_updated timestamp without time zone DEFAULT now(),
  created_at timestamp without time zone DEFAULT now(),
  CONSTRAINT ai_players_pkey PRIMARY KEY (id),
  CONSTRAINT ai_players_universe_id_fkey FOREIGN KEY (universe_id) REFERENCES public.universes(id)
);
CREATE TABLE public.ai_ranking_history (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  ai_player_id uuid,
  universe_id uuid,
  rank_position integer,
  total_score integer,
  economic_score integer,
  territorial_score integer,
  military_score integer,
  exploration_score integer,
  recorded_at timestamp without time zone DEFAULT now(),
  CONSTRAINT ai_ranking_history_pkey PRIMARY KEY (id),
  CONSTRAINT ai_ranking_history_ai_player_id_fkey FOREIGN KEY (ai_player_id) REFERENCES public.ai_players(id),
  CONSTRAINT ai_ranking_history_universe_id_fkey FOREIGN KEY (universe_id) REFERENCES public.universes(id)
);
CREATE TABLE public.combats (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  attacker_id uuid NOT NULL,
  defender_id uuid NOT NULL,
  outcome text,
  snapshot jsonb,
  at timestamp with time zone DEFAULT now(),
  CONSTRAINT combats_pkey PRIMARY KEY (id),
  CONSTRAINT combats_attacker_id_fkey FOREIGN KEY (attacker_id) REFERENCES public.players(id),
  CONSTRAINT combats_defender_id_fkey FOREIGN KEY (defender_id) REFERENCES public.players(id)
);
CREATE TABLE public.cron_logs (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  universe_id uuid NOT NULL,
  event_type text NOT NULL,
  event_name text NOT NULL,
  status text NOT NULL,
  message text,
  execution_time_ms integer,
  triggered_at timestamp with time zone DEFAULT now(),
  metadata jsonb DEFAULT '{}'::jsonb,
  CONSTRAINT cron_logs_pkey PRIMARY KEY (id),
  CONSTRAINT cron_logs_universe_id_fkey FOREIGN KEY (universe_id) REFERENCES public.universes(id)
);
CREATE TABLE public.favorites (
  player_id uuid NOT NULL,
  sector_id uuid NOT NULL,
  CONSTRAINT favorites_pkey PRIMARY KEY (sector_id, player_id),
  CONSTRAINT favorites_player_id_fkey FOREIGN KEY (player_id) REFERENCES public.players(id),
  CONSTRAINT favorites_sector_id_fkey FOREIGN KEY (sector_id) REFERENCES public.sectors(id)
);
CREATE TABLE public.inventories (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  player_id uuid NOT NULL UNIQUE,
  ore integer DEFAULT 0,
  organics integer DEFAULT 0,
  goods integer DEFAULT 0,
  energy integer DEFAULT 0,
  created_at timestamp with time zone DEFAULT now(),
  colonists integer DEFAULT 0 CHECK (colonists >= 0),
  CONSTRAINT inventories_pkey PRIMARY KEY (id),
  CONSTRAINT inventories_player_id_fkey FOREIGN KEY (player_id) REFERENCES public.players(id)
);
CREATE TABLE public.mine_hits (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  player_id uuid NOT NULL,
  mine_id uuid NOT NULL,
  sector_id uuid NOT NULL,
  universe_id uuid NOT NULL,
  damage_taken integer DEFAULT 0 CHECK (damage_taken >= 0),
  ship_destroyed boolean DEFAULT false,
  hull_level_at_hit integer DEFAULT 0 CHECK (hull_level_at_hit >= 0),
  hit_at timestamp with time zone DEFAULT now(),
  CONSTRAINT mine_hits_pkey PRIMARY KEY (id),
  CONSTRAINT mine_hits_player_id_fkey FOREIGN KEY (player_id) REFERENCES public.players(id),
  CONSTRAINT mine_hits_mine_id_fkey FOREIGN KEY (mine_id) REFERENCES public.mines(id),
  CONSTRAINT mine_hits_sector_id_fkey FOREIGN KEY (sector_id) REFERENCES public.sectors(id),
  CONSTRAINT mine_hits_universe_id_fkey FOREIGN KEY (universe_id) REFERENCES public.universes(id)
);
CREATE TABLE public.mines (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  sector_id uuid NOT NULL,
  universe_id uuid NOT NULL,
  deployed_by uuid NOT NULL,
  torpedoes_used integer DEFAULT 1 CHECK (torpedoes_used > 0),
  damage_potential integer DEFAULT 100 CHECK (damage_potential > 0),
  is_active boolean DEFAULT true,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT mines_pkey PRIMARY KEY (id),
  CONSTRAINT mines_sector_id_fkey FOREIGN KEY (sector_id) REFERENCES public.sectors(id),
  CONSTRAINT mines_universe_id_fkey FOREIGN KEY (universe_id) REFERENCES public.universes(id),
  CONSTRAINT mines_deployed_by_fkey FOREIGN KEY (deployed_by) REFERENCES public.players(id)
);
CREATE TABLE public.planets (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  sector_id uuid UNIQUE,
  owner_player_id uuid,
  name text,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT planets_pkey PRIMARY KEY (id),
  CONSTRAINT planets_sector_id_fkey FOREIGN KEY (sector_id) REFERENCES public.sectors(id),
  CONSTRAINT planets_owner_player_id_fkey FOREIGN KEY (owner_player_id) REFERENCES public.players(id)
);
CREATE TABLE public.player_rankings (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  player_id uuid,
  universe_id uuid,
  economic_score integer DEFAULT 0,
  territorial_score integer DEFAULT 0,
  military_score integer DEFAULT 0,
  exploration_score integer DEFAULT 0,
  total_score integer DEFAULT 0,
  rank_position integer,
  last_updated timestamp without time zone DEFAULT now(),
  created_at timestamp without time zone DEFAULT now(),
  CONSTRAINT player_rankings_pkey PRIMARY KEY (id),
  CONSTRAINT player_rankings_player_id_fkey FOREIGN KEY (player_id) REFERENCES public.players(id),
  CONSTRAINT player_rankings_universe_id_fkey FOREIGN KEY (universe_id) REFERENCES public.universes(id)
);
CREATE TABLE public.players (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  universe_id uuid NOT NULL,
  handle text NOT NULL,
  credits bigint DEFAULT 1000,
  turns integer DEFAULT 60,
  current_sector uuid,
  last_turn_ts timestamp with time zone DEFAULT now(),
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT players_pkey PRIMARY KEY (id),
  CONSTRAINT players_universe_id_fkey FOREIGN KEY (universe_id) REFERENCES public.universes(id),
  CONSTRAINT players_current_sector_fkey FOREIGN KEY (current_sector) REFERENCES public.sectors(id)
);
CREATE TABLE public.ports (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  sector_id uuid NOT NULL UNIQUE,
  kind text DEFAULT 'trade'::text,
  ore integer DEFAULT 0,
  organics integer DEFAULT 0,
  goods integer DEFAULT 0,
  energy integer DEFAULT 0,
  price_ore numeric DEFAULT 10.0,
  price_organics numeric DEFAULT 15.0,
  price_goods numeric DEFAULT 25.0,
  price_energy numeric DEFAULT 5.0,
  created_at timestamp with time zone DEFAULT now(),
  stock_enforced boolean NOT NULL DEFAULT false,
  CONSTRAINT ports_pkey PRIMARY KEY (id),
  CONSTRAINT ports_sector_id_fkey FOREIGN KEY (sector_id) REFERENCES public.sectors(id)
);
CREATE TABLE public.ranking_history (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  player_id uuid,
  universe_id uuid,
  rank_position integer,
  total_score integer,
  economic_score integer,
  territorial_score integer,
  military_score integer,
  exploration_score integer,
  recorded_at timestamp without time zone DEFAULT now(),
  CONSTRAINT ranking_history_pkey PRIMARY KEY (id),
  CONSTRAINT ranking_history_player_id_fkey FOREIGN KEY (player_id) REFERENCES public.players(id),
  CONSTRAINT ranking_history_universe_id_fkey FOREIGN KEY (universe_id) REFERENCES public.universes(id)
);
CREATE TABLE public.route_executions (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  route_id uuid NOT NULL,
  player_id uuid NOT NULL,
  started_at timestamp with time zone DEFAULT now(),
  completed_at timestamp with time zone,
  status text DEFAULT 'running'::text CHECK (status = ANY (ARRAY['running'::text, 'completed'::text, 'failed'::text, 'paused'::text])),
  current_waypoint integer DEFAULT 1,
  total_profit bigint DEFAULT 0,
  turns_spent integer DEFAULT 0,
  error_message text,
  execution_data jsonb DEFAULT '{}'::jsonb,
  CONSTRAINT route_executions_pkey PRIMARY KEY (id),
  CONSTRAINT route_executions_route_id_fkey FOREIGN KEY (route_id) REFERENCES public.trade_routes(id),
  CONSTRAINT route_executions_player_id_fkey FOREIGN KEY (player_id) REFERENCES public.players(id)
);
CREATE TABLE public.route_profitability (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  route_id uuid NOT NULL,
  calculated_at timestamp with time zone DEFAULT now(),
  estimated_profit_per_cycle bigint,
  estimated_turns_per_cycle integer,
  profit_per_turn numeric,
  cargo_efficiency numeric,
  market_conditions jsonb DEFAULT '{}'::jsonb,
  is_current boolean DEFAULT true,
  CONSTRAINT route_profitability_pkey PRIMARY KEY (id),
  CONSTRAINT route_profitability_route_id_fkey FOREIGN KEY (route_id) REFERENCES public.trade_routes(id)
);
CREATE TABLE public.route_templates (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  name text NOT NULL,
  description text,
  template_data jsonb NOT NULL,
  difficulty_level integer DEFAULT 1 CHECK (difficulty_level >= 1 AND difficulty_level <= 5),
  required_engine_level integer DEFAULT 1,
  required_cargo_capacity integer DEFAULT 1000,
  estimated_profit_per_turn numeric,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT route_templates_pkey PRIMARY KEY (id)
);
CREATE TABLE public.route_waypoints (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  route_id uuid NOT NULL,
  sequence_order integer NOT NULL,
  port_id uuid NOT NULL,
  action_type text NOT NULL CHECK (action_type = ANY (ARRAY['buy'::text, 'sell'::text, 'trade_auto'::text])),
  resource text CHECK (resource = ANY (ARRAY['ore'::text, 'organics'::text, 'goods'::text, 'energy'::text])),
  quantity integer DEFAULT 0,
  notes text,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT route_waypoints_pkey PRIMARY KEY (id),
  CONSTRAINT route_waypoints_route_id_fkey FOREIGN KEY (route_id) REFERENCES public.trade_routes(id),
  CONSTRAINT route_waypoints_port_id_fkey FOREIGN KEY (port_id) REFERENCES public.ports(id)
);
CREATE TABLE public.scans (
  player_id uuid NOT NULL,
  sector_id uuid NOT NULL,
  mode text CHECK (mode = ANY (ARRAY['single'::text, 'full'::text])),
  scanned_at timestamp with time zone DEFAULT now(),
  CONSTRAINT scans_pkey PRIMARY KEY (player_id, sector_id),
  CONSTRAINT scans_player_id_fkey FOREIGN KEY (player_id) REFERENCES public.players(id),
  CONSTRAINT scans_sector_id_fkey FOREIGN KEY (sector_id) REFERENCES public.sectors(id)
);
CREATE TABLE public.sectors (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  universe_id uuid NOT NULL,
  number integer NOT NULL,
  meta jsonb DEFAULT '{}'::jsonb,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT sectors_pkey PRIMARY KEY (id),
  CONSTRAINT sectors_universe_id_fkey FOREIGN KEY (universe_id) REFERENCES public.universes(id)
);
CREATE TABLE public.ships (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  player_id uuid NOT NULL UNIQUE,
  name text DEFAULT 'Scout'::text,
  hull integer DEFAULT 100,
  shield integer DEFAULT 0,
  fighters integer DEFAULT 0 CHECK (fighters >= 0),
  torpedoes integer DEFAULT 0 CHECK (torpedoes >= 0),
  engine_lvl integer DEFAULT 1,
  created_at timestamp with time zone DEFAULT now(),
  hull_max integer DEFAULT 100,
  shield_lvl integer DEFAULT 0,
  shield_max integer DEFAULT (20 * GREATEST(shield_lvl, 0)),
  comp_lvl integer DEFAULT 1,
  sensor_lvl integer DEFAULT 1,
  hull_lvl integer DEFAULT 1,
  cargo integer DEFAULT 1000,
  armor integer DEFAULT 0,
  armor_max integer DEFAULT 0,
  device_space_beacons integer DEFAULT 0 CHECK (device_space_beacons >= 0),
  device_warp_editors integer DEFAULT 0 CHECK (device_warp_editors >= 0),
  device_genesis_torpedoes integer DEFAULT 0 CHECK (device_genesis_torpedoes >= 0),
  device_mine_deflectors integer DEFAULT 0 CHECK (device_mine_deflectors >= 0),
  device_emergency_warp boolean DEFAULT false,
  device_escape_pod boolean DEFAULT true,
  device_fuel_scoop boolean DEFAULT false,
  device_last_seen boolean DEFAULT false,
  power_lvl integer DEFAULT 1 CHECK (power_lvl >= 0),
  beam_lvl integer DEFAULT 0 CHECK (beam_lvl >= 0),
  torp_launcher_lvl integer DEFAULT 0 CHECK (torp_launcher_lvl >= 0),
  cloak_lvl integer DEFAULT 0 CHECK (cloak_lvl >= 0),
  colonists integer DEFAULT 0 CHECK (colonists >= 0),
  energy integer DEFAULT 0,
  energy_max integer DEFAULT 0,
  CONSTRAINT ships_pkey PRIMARY KEY (id),
  CONSTRAINT ships_player_id_fkey FOREIGN KEY (player_id) REFERENCES public.players(id)
);
CREATE TABLE public.trade_routes (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  player_id uuid NOT NULL,
  universe_id uuid NOT NULL,
  name text NOT NULL,
  description text,
  is_active boolean DEFAULT false,
  is_automated boolean DEFAULT false,
  max_iterations integer DEFAULT 0,
  current_iteration integer DEFAULT 0,
  total_profit bigint DEFAULT 0,
  total_turns_spent integer DEFAULT 0,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  last_executed_at timestamp with time zone,
  movement_type text DEFAULT 'warp'::text CHECK (movement_type = ANY (ARRAY['warp'::text, 'realspace'::text])),
  CONSTRAINT trade_routes_pkey PRIMARY KEY (id),
  CONSTRAINT trade_routes_player_id_fkey FOREIGN KEY (player_id) REFERENCES public.players(id),
  CONSTRAINT trade_routes_universe_id_fkey FOREIGN KEY (universe_id) REFERENCES public.universes(id)
);
CREATE TABLE public.trades (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  player_id uuid NOT NULL,
  port_id uuid NOT NULL,
  action text NOT NULL CHECK (action = ANY (ARRAY['buy'::text, 'sell'::text])),
  resource text NOT NULL CHECK (resource = ANY (ARRAY['ore'::text, 'organics'::text, 'goods'::text, 'energy'::text, 'fighters'::text, 'torpedoes'::text, 'hull_repair'::text])),
  qty integer NOT NULL,
  price numeric NOT NULL,
  at timestamp with time zone DEFAULT now(),
  quantity bigint,
  unit_price numeric,
  total_price numeric,
  CONSTRAINT trades_pkey PRIMARY KEY (id),
  CONSTRAINT trades_player_id_fkey FOREIGN KEY (player_id) REFERENCES public.players(id),
  CONSTRAINT trades_port_id_fkey FOREIGN KEY (port_id) REFERENCES public.ports(id)
);
CREATE TABLE public.universe_settings (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  universe_id uuid NOT NULL UNIQUE,
  game_version text DEFAULT '0.663'::text,
  game_name text DEFAULT 'BNT Redux'::text,
  avg_tech_level_mines integer DEFAULT 13,
  avg_tech_emergency_warp_degrade integer DEFAULT 15,
  max_avg_tech_federation_sectors integer DEFAULT 8,
  tech_level_upgrade_bases integer DEFAULT 1,
  number_of_sectors integer DEFAULT 1000 CHECK (number_of_sectors > 0),
  max_links_per_sector integer DEFAULT 10 CHECK (max_links_per_sector > 0),
  max_planets_per_sector integer DEFAULT 10,
  planets_needed_for_sector_ownership integer DEFAULT 5,
  igb_enabled boolean DEFAULT true,
  igb_interest_rate_per_update numeric DEFAULT 0.05,
  igb_loan_rate_per_update numeric DEFAULT 0.1,
  planet_interest_rate numeric DEFAULT 0.06,
  colonists_limit bigint DEFAULT '100000000000'::bigint,
  colonist_production_rate numeric DEFAULT 0.005,
  colonists_per_fighter integer DEFAULT 20000,
  colonists_per_torpedo integer DEFAULT 8000,
  colonists_per_ore integer DEFAULT 800,
  colonists_per_organics integer DEFAULT 400,
  colonists_per_goods integer DEFAULT 800,
  colonists_per_energy integer DEFAULT 400,
  colonists_per_credits integer DEFAULT 67,
  max_accumulated_turns integer DEFAULT 5000,
  max_traderoutes_per_player integer DEFAULT 40,
  energy_per_sector_fighter numeric DEFAULT 0.1,
  sector_fighter_degradation_rate numeric DEFAULT 5.0,
  tick_interval_minutes integer DEFAULT 6,
  turns_generation_interval_minutes integer DEFAULT 3,
  turns_per_generation integer DEFAULT 12 CHECK (turns_per_generation > 0),
  defenses_check_interval_minutes integer DEFAULT 3,
  xenobes_play_interval_minutes integer DEFAULT 3,
  igb_interest_accumulation_interval_minutes integer DEFAULT 2,
  news_generation_interval_minutes integer DEFAULT 6,
  planet_production_interval_minutes integer DEFAULT 2,
  port_regeneration_interval_minutes integer DEFAULT 1,
  ships_tow_from_fed_sectors_interval_minutes integer DEFAULT 3,
  rankings_generation_interval_minutes integer DEFAULT 1,
  sector_defenses_degrade_interval_minutes integer DEFAULT 6,
  planetary_apocalypse_interval_minutes integer DEFAULT 60,
  use_new_planet_update_code boolean DEFAULT true,
  limit_captured_planets_max_credits boolean DEFAULT false,
  captured_planets_max_credits bigint DEFAULT 1000000000,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  created_by uuid,
  updated_by uuid,
  turn_generation_interval_minutes integer DEFAULT 3 CHECK (turn_generation_interval_minutes > 0),
  cycle_interval_minutes integer DEFAULT 6 CHECK (cycle_interval_minutes > 0),
  update_interval_minutes integer DEFAULT 1 CHECK (update_interval_minutes > 0),
  last_turn_generation timestamp with time zone,
  last_cycle_event timestamp with time zone,
  last_update_event timestamp with time zone,
  avg_tech_level_emergency_warp_degrades integer DEFAULT 15,
  last_port_regeneration_event timestamp with time zone,
  last_rankings_generation_event timestamp with time zone,
  last_defenses_check_event timestamp with time zone,
  last_xenobes_play_event timestamp with time zone,
  last_igb_interest_accumulation_event timestamp with time zone,
  last_news_generation_event timestamp with time zone,
  last_planet_production_event timestamp with time zone,
  last_ships_tow_from_fed_sectors_event timestamp with time zone,
  last_sector_defenses_degrade_event timestamp with time zone,
  last_planetary_apocalypse_event timestamp with time zone,
  CONSTRAINT universe_settings_pkey PRIMARY KEY (id),
  CONSTRAINT universe_settings_universe_id_fkey FOREIGN KEY (universe_id) REFERENCES public.universes(id),
  CONSTRAINT universe_settings_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id),
  CONSTRAINT universe_settings_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES auth.users(id)
);
CREATE TABLE public.universes (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  name text NOT NULL UNIQUE,
  sector_count integer NOT NULL,
  active boolean DEFAULT true,
  created_at timestamp with time zone DEFAULT now(),
  ai_player_count integer DEFAULT 0,
  CONSTRAINT universes_pkey PRIMARY KEY (id)
);
CREATE TABLE public.upgrade_costs (
  level integer NOT NULL,
  cost integer NOT NULL,
  CONSTRAINT upgrade_costs_pkey PRIMARY KEY (level)
);
CREATE TABLE public.user_profiles (
  user_id uuid NOT NULL,
  is_admin boolean NOT NULL DEFAULT false,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT user_profiles_pkey PRIMARY KEY (user_id)
);
CREATE TABLE public.visited (
  player_id uuid NOT NULL,
  sector_id uuid NOT NULL,
  first_seen timestamp with time zone DEFAULT now(),
  last_seen timestamp with time zone DEFAULT now(),
  CONSTRAINT visited_pkey PRIMARY KEY (sector_id, player_id),
  CONSTRAINT visited_player_id_fkey FOREIGN KEY (player_id) REFERENCES public.players(id),
  CONSTRAINT visited_sector_id_fkey FOREIGN KEY (sector_id) REFERENCES public.sectors(id)
);
CREATE TABLE public.warps (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  universe_id uuid NOT NULL,
  from_sector uuid NOT NULL,
  to_sector uuid NOT NULL,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT warps_pkey PRIMARY KEY (id),
  CONSTRAINT warps_universe_id_fkey FOREIGN KEY (universe_id) REFERENCES public.universes(id),
  CONSTRAINT warps_from_sector_fkey FOREIGN KEY (from_sector) REFERENCES public.sectors(id),
  CONSTRAINT warps_to_sector_fkey FOREIGN KEY (to_sector) REFERENCES public.sectors(id)
);