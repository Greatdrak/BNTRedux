import { supabaseAdmin } from '@/lib/supabase-server'

export interface UniverseSettings {
  universe_id?: string
  max_accumulated_turns: number
  turns_generation_interval_minutes: number | null
  port_regeneration_interval_minutes: number | null
  rankings_generation_interval_minutes: number | null
  defenses_check_interval_minutes: number | null
  xenobes_play_interval_minutes: number | null
  igb_interest_accumulation_interval_minutes: number | null
  news_generation_interval_minutes: number | null
  planet_production_interval_minutes: number | null
  ships_tow_from_fed_sectors_interval_minutes: number | null
  sector_defenses_degrade_interval_minutes: number | null
  planetary_apocalypse_interval_minutes: number | null
  // Last-run timestamps
  last_turn_generation?: string | null
  last_port_regeneration_event?: string | null
  last_rankings_generation_event?: string | null
  last_defenses_check_event?: string | null
  last_xenobes_play_event?: string | null
  last_igb_interest_accumulation_event?: string | null
  last_news_generation_event?: string | null
  last_planet_production_event?: string | null
  last_ships_tow_from_fed_sectors_event?: string | null
  last_sector_defenses_degrade_event?: string | null
  last_planetary_apocalypse_event?: string | null
}

const DEFAULT_SETTINGS: UniverseSettings = {
  max_accumulated_turns: 5000,
  turns_generation_interval_minutes: 3,
  port_regeneration_interval_minutes: 5,  // Changed from 1 to 5 minutes
  rankings_generation_interval_minutes: 10,  // Changed from 1 to 10 minutes
  defenses_check_interval_minutes: 15,  // Changed from 3 to 15 minutes
  xenobes_play_interval_minutes: 30,  // Changed from 3 to 30 minutes
  igb_interest_accumulation_interval_minutes: 10,  // Changed from 2 to 10 minutes
  news_generation_interval_minutes: 60,  // Changed from 6 to 60 minutes
  planet_production_interval_minutes: 15,  // Changed from 2 to 15 minutes
  ships_tow_from_fed_sectors_interval_minutes: 30,  // Changed from 3 to 30 minutes
  sector_defenses_degrade_interval_minutes: 60,  // Changed from 6 to 60 minutes
  planetary_apocalypse_interval_minutes: 1440,  // Changed from 60 to 1440 minutes (24 hours)
}

export async function getUniverseSettings(universeId: string): Promise<UniverseSettings> {
  const { data, error } = await supabaseAdmin
    .from('universe_settings')
    .select(`
      universe_id,
      max_accumulated_turns,
      turns_generation_interval_minutes,
      port_regeneration_interval_minutes,
      rankings_generation_interval_minutes,
      defenses_check_interval_minutes,
      xenobes_play_interval_minutes,
      igb_interest_accumulation_interval_minutes,
      news_generation_interval_minutes,
      planet_production_interval_minutes,
      ships_tow_from_fed_sectors_interval_minutes,
      sector_defenses_degrade_interval_minutes,
      planetary_apocalypse_interval_minutes,
      last_turn_generation,
      last_port_regeneration_event,
      last_rankings_generation_event,
      last_defenses_check_event,
      last_xenobes_play_event,
      last_igb_interest_accumulation_event,
      last_news_generation_event,
      last_planet_production_event,
      last_ships_tow_from_fed_sectors_event,
      last_sector_defenses_degrade_event,
      last_planetary_apocalypse_event
    `)
    .eq('universe_id', universeId)
    .single()

  if (error || !data) {
    return { ...DEFAULT_SETTINGS, universe_id: universeId }
  }
  
  return data as UniverseSettings
}


