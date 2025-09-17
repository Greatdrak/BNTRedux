| constraint_statement                                                                                  |
| ----------------------------------------------------------------------------------------------------- |
| ALTER TABLE ai_players ADD CONSTRAINT 2200_19441_1_not_null CHECK;                                    |
| ALTER TABLE ai_players ADD CONSTRAINT 2200_19441_3_not_null CHECK;                                    |
| ALTER TABLE ai_players ADD CONSTRAINT ai_players_ai_type_check CHECK;                                 |
| ALTER TABLE ai_players ADD CONSTRAINT ai_players_name_universe_id_key UNIQUE;                         |
| ALTER TABLE ai_players ADD CONSTRAINT ai_players_pkey PRIMARY KEY;                                    |
| ALTER TABLE ai_players ADD CONSTRAINT ai_players_universe_id_fkey FOREIGN KEY;                        |
| ALTER TABLE ai_ranking_history ADD CONSTRAINT 2200_19482_1_not_null CHECK;                            |
| ALTER TABLE ai_ranking_history ADD CONSTRAINT ai_ranking_history_ai_player_id_fkey FOREIGN KEY;       |
| ALTER TABLE ai_ranking_history ADD CONSTRAINT ai_ranking_history_pkey PRIMARY KEY;                    |
| ALTER TABLE ai_ranking_history ADD CONSTRAINT ai_ranking_history_universe_id_fkey FOREIGN KEY;        |
| ALTER TABLE combats ADD CONSTRAINT 2200_17468_1_not_null CHECK;                                       |
| ALTER TABLE combats ADD CONSTRAINT 2200_17468_2_not_null CHECK;                                       |
| ALTER TABLE combats ADD CONSTRAINT 2200_17468_3_not_null CHECK;                                       |
| ALTER TABLE combats ADD CONSTRAINT combats_attacker_id_fkey FOREIGN KEY;                              |
| ALTER TABLE combats ADD CONSTRAINT combats_defender_id_fkey FOREIGN KEY;                              |
| ALTER TABLE combats ADD CONSTRAINT combats_pkey PRIMARY KEY;                                          |
| ALTER TABLE favorites ADD CONSTRAINT 2200_17854_1_not_null CHECK;                                     |
| ALTER TABLE favorites ADD CONSTRAINT 2200_17854_2_not_null CHECK;                                     |
| ALTER TABLE favorites ADD CONSTRAINT favorites_pkey PRIMARY KEY;                                      |
| ALTER TABLE favorites ADD CONSTRAINT favorites_player_id_fkey FOREIGN KEY;                            |
| ALTER TABLE favorites ADD CONSTRAINT favorites_sector_id_fkey FOREIGN KEY;                            |
| ALTER TABLE inventories ADD CONSTRAINT 2200_17429_1_not_null CHECK;                                   |
| ALTER TABLE inventories ADD CONSTRAINT 2200_17429_2_not_null CHECK;                                   |
| ALTER TABLE inventories ADD CONSTRAINT inventories_pkey PRIMARY KEY;                                  |
| ALTER TABLE inventories ADD CONSTRAINT inventories_player_id_fkey FOREIGN KEY;                        |
| ALTER TABLE inventories ADD CONSTRAINT inventories_player_id_key UNIQUE;                              |
| ALTER TABLE planets ADD CONSTRAINT 2200_17869_1_not_null CHECK;                                       |
| ALTER TABLE planets ADD CONSTRAINT planets_owner_player_id_fkey FOREIGN KEY;                          |
| ALTER TABLE planets ADD CONSTRAINT planets_pkey PRIMARY KEY;                                          |
| ALTER TABLE planets ADD CONSTRAINT planets_sector_id_fkey FOREIGN KEY;                                |
| ALTER TABLE planets ADD CONSTRAINT planets_unique_sector UNIQUE;                                      |
| ALTER TABLE player_rankings ADD CONSTRAINT 2200_19416_1_not_null CHECK;                               |
| ALTER TABLE player_rankings ADD CONSTRAINT player_rankings_pkey PRIMARY KEY;                          |
| ALTER TABLE player_rankings ADD CONSTRAINT player_rankings_player_id_fkey FOREIGN KEY;                |
| ALTER TABLE player_rankings ADD CONSTRAINT player_rankings_player_id_universe_id_key UNIQUE;          |
| ALTER TABLE player_rankings ADD CONSTRAINT player_rankings_universe_id_fkey FOREIGN KEY;              |
| ALTER TABLE players ADD CONSTRAINT 2200_17381_1_not_null CHECK;                                       |
| ALTER TABLE players ADD CONSTRAINT 2200_17381_2_not_null CHECK;                                       |
| ALTER TABLE players ADD CONSTRAINT 2200_17381_3_not_null CHECK;                                       |
| ALTER TABLE players ADD CONSTRAINT 2200_17381_4_not_null CHECK;                                       |
| ALTER TABLE players ADD CONSTRAINT players_current_sector_fkey FOREIGN KEY;                           |
| ALTER TABLE players ADD CONSTRAINT players_pkey PRIMARY KEY;                                          |
| ALTER TABLE players ADD CONSTRAINT players_universe_id_fkey FOREIGN KEY;                              |
| ALTER TABLE players ADD CONSTRAINT players_universe_id_handle_key UNIQUE;                             |
| ALTER TABLE ports ADD CONSTRAINT 2200_17356_13_not_null CHECK;                                        |
| ALTER TABLE ports ADD CONSTRAINT 2200_17356_1_not_null CHECK;                                         |
| ALTER TABLE ports ADD CONSTRAINT 2200_17356_2_not_null CHECK;                                         |
| ALTER TABLE ports ADD CONSTRAINT ports_pkey PRIMARY KEY;                                              |
| ALTER TABLE ports ADD CONSTRAINT ports_sector_id_fkey FOREIGN KEY;                                    |
| ALTER TABLE ports ADD CONSTRAINT ports_sector_id_key UNIQUE;                                          |
| ALTER TABLE ranking_history ADD CONSTRAINT 2200_19465_1_not_null CHECK;                               |
| ALTER TABLE ranking_history ADD CONSTRAINT ranking_history_pkey PRIMARY KEY;                          |
| ALTER TABLE ranking_history ADD CONSTRAINT ranking_history_player_id_fkey FOREIGN KEY;                |
| ALTER TABLE ranking_history ADD CONSTRAINT ranking_history_universe_id_fkey FOREIGN KEY;              |
| ALTER TABLE route_executions ADD CONSTRAINT 2200_19628_1_not_null CHECK;                              |
| ALTER TABLE route_executions ADD CONSTRAINT 2200_19628_2_not_null CHECK;                              |
| ALTER TABLE route_executions ADD CONSTRAINT 2200_19628_3_not_null CHECK;                              |
| ALTER TABLE route_executions ADD CONSTRAINT route_executions_pkey PRIMARY KEY;                        |
| ALTER TABLE route_executions ADD CONSTRAINT route_executions_player_id_fkey FOREIGN KEY;              |
| ALTER TABLE route_executions ADD CONSTRAINT route_executions_route_id_fkey FOREIGN KEY;               |
| ALTER TABLE route_executions ADD CONSTRAINT route_executions_status_check CHECK;                      |
| ALTER TABLE route_profitability ADD CONSTRAINT 2200_19653_1_not_null CHECK;                           |
| ALTER TABLE route_profitability ADD CONSTRAINT 2200_19653_2_not_null CHECK;                           |
| ALTER TABLE route_profitability ADD CONSTRAINT route_profitability_pkey PRIMARY KEY;                  |
| ALTER TABLE route_profitability ADD CONSTRAINT route_profitability_route_id_calculated_at_key UNIQUE; |
| ALTER TABLE route_profitability ADD CONSTRAINT route_profitability_route_id_fkey FOREIGN KEY;         |
| ALTER TABLE route_templates ADD CONSTRAINT 2200_19671_1_not_null CHECK;                               |
| ALTER TABLE route_templates ADD CONSTRAINT 2200_19671_2_not_null CHECK;                               |
| ALTER TABLE route_templates ADD CONSTRAINT 2200_19671_4_not_null CHECK;                               |
| ALTER TABLE route_templates ADD CONSTRAINT route_templates_difficulty_level_check CHECK;              |
| ALTER TABLE route_templates ADD CONSTRAINT route_templates_pkey PRIMARY KEY;                          |
| ALTER TABLE route_waypoints ADD CONSTRAINT 2200_19604_1_not_null CHECK;                               |
| ALTER TABLE route_waypoints ADD CONSTRAINT 2200_19604_2_not_null CHECK;                               |
| ALTER TABLE route_waypoints ADD CONSTRAINT 2200_19604_3_not_null CHECK;                               |
| ALTER TABLE route_waypoints ADD CONSTRAINT 2200_19604_4_not_null CHECK;                               |
| ALTER TABLE route_waypoints ADD CONSTRAINT 2200_19604_5_not_null CHECK;                               |
| ALTER TABLE route_waypoints ADD CONSTRAINT route_waypoints_action_type_check CHECK;                   |
| ALTER TABLE route_waypoints ADD CONSTRAINT route_waypoints_pkey PRIMARY KEY;                          |
| ALTER TABLE route_waypoints ADD CONSTRAINT route_waypoints_port_id_fkey FOREIGN KEY;                  |
| ALTER TABLE route_waypoints ADD CONSTRAINT route_waypoints_resource_check CHECK;                      |
| ALTER TABLE route_waypoints ADD CONSTRAINT route_waypoints_route_id_fkey FOREIGN KEY;                 |
| ALTER TABLE route_waypoints ADD CONSTRAINT route_waypoints_route_id_sequence_order_key UNIQUE;        |
| ALTER TABLE scans ADD CONSTRAINT 2200_17835_1_not_null CHECK;                                         |
| ALTER TABLE scans ADD CONSTRAINT 2200_17835_2_not_null CHECK;                                         |
| ALTER TABLE scans ADD CONSTRAINT scans_mode_check CHECK;                                              |
| ALTER TABLE scans ADD CONSTRAINT scans_pkey PRIMARY KEY;                                              |
| ALTER TABLE scans ADD CONSTRAINT scans_player_id_fkey FOREIGN KEY;                                    |
| ALTER TABLE scans ADD CONSTRAINT scans_sector_id_fkey FOREIGN KEY;                                    |
| ALTER TABLE sectors ADD CONSTRAINT 2200_17314_1_not_null CHECK;                                       |
| ALTER TABLE sectors ADD CONSTRAINT 2200_17314_2_not_null CHECK;                                       |
| ALTER TABLE sectors ADD CONSTRAINT 2200_17314_3_not_null CHECK;                                       |
| ALTER TABLE sectors ADD CONSTRAINT sectors_pkey PRIMARY KEY;                                          |
| ALTER TABLE sectors ADD CONSTRAINT sectors_universe_id_fkey FOREIGN KEY;                              |
| ALTER TABLE sectors ADD CONSTRAINT sectors_universe_id_number_key UNIQUE;                             |
| ALTER TABLE ships ADD CONSTRAINT 2200_17406_1_not_null CHECK;                                         |
| ALTER TABLE ships ADD CONSTRAINT 2200_17406_2_not_null CHECK;                                         |
| ALTER TABLE ships ADD CONSTRAINT ships_hull_range CHECK;                                              |
| ALTER TABLE ships ADD CONSTRAINT ships_pkey PRIMARY KEY;                                              |
| ALTER TABLE ships ADD CONSTRAINT ships_player_id_fkey FOREIGN KEY;                                    |
| ALTER TABLE ships ADD CONSTRAINT ships_player_id_key UNIQUE;                                          |
| ALTER TABLE ships ADD CONSTRAINT ships_shield_range CHECK;                                            |
| ALTER TABLE trade_routes ADD CONSTRAINT 2200_19576_1_not_null CHECK;                                  |
| ALTER TABLE trade_routes ADD CONSTRAINT 2200_19576_2_not_null CHECK;                                  |
| ALTER TABLE trade_routes ADD CONSTRAINT 2200_19576_3_not_null CHECK;                                  |
| ALTER TABLE trade_routes ADD CONSTRAINT 2200_19576_4_not_null CHECK;                                  |
| ALTER TABLE trade_routes ADD CONSTRAINT trade_routes_movement_type_check CHECK;                       |
| ALTER TABLE trade_routes ADD CONSTRAINT trade_routes_pkey PRIMARY KEY;                                |
| ALTER TABLE trade_routes ADD CONSTRAINT trade_routes_player_id_fkey FOREIGN KEY;                      |
| ALTER TABLE trade_routes ADD CONSTRAINT trade_routes_player_id_name_key UNIQUE;                       |
| ALTER TABLE trade_routes ADD CONSTRAINT trade_routes_universe_id_fkey FOREIGN KEY;                    |
| ALTER TABLE trades ADD CONSTRAINT 2200_17447_1_not_null CHECK;                                        |
| ALTER TABLE trades ADD CONSTRAINT 2200_17447_2_not_null CHECK;                                        |
| ALTER TABLE trades ADD CONSTRAINT 2200_17447_3_not_null CHECK;                                        |
| ALTER TABLE trades ADD CONSTRAINT 2200_17447_4_not_null CHECK;                                        |
| ALTER TABLE trades ADD CONSTRAINT 2200_17447_5_not_null CHECK;                                        |
| ALTER TABLE trades ADD CONSTRAINT 2200_17447_6_not_null CHECK;                                        |
| ALTER TABLE trades ADD CONSTRAINT 2200_17447_7_not_null CHECK;                                        |
| ALTER TABLE trades ADD CONSTRAINT trades_action_check CHECK;                                          |
| ALTER TABLE trades ADD CONSTRAINT trades_pkey PRIMARY KEY;                                            |
| ALTER TABLE trades ADD CONSTRAINT trades_player_id_fkey FOREIGN KEY;                                  |
| ALTER TABLE trades ADD CONSTRAINT trades_port_id_fkey FOREIGN KEY;                                    |
| ALTER TABLE trades ADD CONSTRAINT trades_resource_check CHECK;                                        |
| ALTER TABLE universes ADD CONSTRAINT 2200_17302_1_not_null CHECK;                                     |
| ALTER TABLE universes ADD CONSTRAINT 2200_17302_2_not_null CHECK;                                     |
| ALTER TABLE universes ADD CONSTRAINT 2200_17302_3_not_null CHECK;                                     |
| ALTER TABLE universes ADD CONSTRAINT universes_name_key UNIQUE;                                       |
| ALTER TABLE universes ADD CONSTRAINT universes_pkey PRIMARY KEY;                                      |
| ALTER TABLE visited ADD CONSTRAINT 2200_17818_1_not_null CHECK;                                       |
| ALTER TABLE visited ADD CONSTRAINT 2200_17818_2_not_null CHECK;                                       |
| ALTER TABLE visited ADD CONSTRAINT visited_pkey PRIMARY KEY;                                          |
| ALTER TABLE visited ADD CONSTRAINT visited_player_id_fkey FOREIGN KEY;                                |
| ALTER TABLE visited ADD CONSTRAINT visited_sector_id_fkey FOREIGN KEY;                                |
| ALTER TABLE warps ADD CONSTRAINT 2200_17331_1_not_null CHECK;                                         |
| ALTER TABLE warps ADD CONSTRAINT 2200_17331_2_not_null CHECK;                                         |
| ALTER TABLE warps ADD CONSTRAINT 2200_17331_3_not_null CHECK;                                         |
| ALTER TABLE warps ADD CONSTRAINT 2200_17331_4_not_null CHECK;                                         |
| ALTER TABLE warps ADD CONSTRAINT warps_check CHECK;                                                   |
| ALTER TABLE warps ADD CONSTRAINT warps_from_sector_fkey FOREIGN KEY;                                  |
| ALTER TABLE warps ADD CONSTRAINT warps_pkey PRIMARY KEY;                                              |
| ALTER TABLE warps ADD CONSTRAINT warps_to_sector_fkey FOREIGN KEY;                                    |
| ALTER TABLE warps ADD CONSTRAINT warps_universe_id_fkey FOREIGN KEY;                                  |
| ALTER TABLE warps ADD CONSTRAINT warps_universe_id_from_sector_to_sector_key UNIQUE;                  |