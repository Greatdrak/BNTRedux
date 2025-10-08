-- When a player moves, stamp the sector with last visitor (excluding themselves check is done client side on display)
CREATE OR REPLACE FUNCTION public.mark_sector_last_visited(p_player_id uuid, p_sector_id uuid)
RETURNS void AS $$
BEGIN
  UPDATE public.sectors
    SET last_player_visited = p_player_id,
        last_visited_at = now()
    WHERE id = p_sector_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


