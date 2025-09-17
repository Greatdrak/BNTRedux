-- Cleanup Script: Remove Duplicate SQL Files
-- This script identifies which files can be safely deleted

-- Files to KEEP (Essential):
-- 001_init.sql - Core schema
-- 002_seed.sql - Initial data  
-- schema_dump_09162025.sql - Complete schema backup
-- 083_complete_fix.sql - Final working trade route function

-- Files to DELETE (Duplicates/Iterations):
-- 052_implement_trade_route_execution.sql
-- 053_simple_trade_route_execution.sql
-- 054_fix_trade_route_execution.sql
-- 055_fix_trade_route_execution_final.sql
-- 056_proper_trade_route_execution.sql
-- 057_complete_trade_route_execution.sql
-- 058_fix_json_operator_error.sql
-- 059_fix_trade_route_execution_final.sql
-- 060_debug_trade_route_execution.sql
-- 061_test_trade_route_execution.sql
-- 062_debug_trade_function.sql
-- 063_simple_port_check.sql
-- 064_test_manual_trade.sql
-- 065_fix_trade_auto_function.sql
-- 066_fix_trade_route_logic.sql
-- 067_debug_trade_route_execution.sql
-- 068_fix_waypoint_selection.sql
-- 069_fix_inventory_column.sql
-- 070_simple_debug_execution.sql
-- 071_minimal_execution.sql
-- 072_test_function.sql
-- 073_debug_simple.sql
-- 074_clean_trade_route.sql
-- 075_test_functions.sql
-- 076_connect_sectors_93_103.sql
-- 077_trade_route_with_movement_types.sql
-- 078_add_movement_type_to_trade_routes.sql
-- 079_update_existing_route_to_realspace.sql
-- 080_final_execute_trade_route.sql
-- 081_diagnose_trade_route.sql
-- 082_force_update_execute_function.sql
-- 084_export_schema.sql

-- Files to CONSOLIDATE:
-- Merge core RPC functions into logical groups
-- Create single comprehensive files for each major feature


