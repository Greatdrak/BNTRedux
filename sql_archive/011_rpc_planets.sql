-- Planets RPCs (claim, store, withdraw)
-- How to apply: Run this after 010_planets_schema.sql in Supabase SQL Editor.

-- Claim a planet in a sector
CREATE OR REPLACE FUNCTION game_planet_claim(
    p_user_id UUID,
    p_sector_number INT,
    p_name TEXT DEFAULT 'Colony'
)
RETURNS JSON AS $$
DECLARE
    v_player_id UUID;
    v_sector_id UUID;
    v_universe_id UUID;
    v_planet_id UUID;
BEGIN
    -- Find player by auth user_id
    SELECT p.id, s.universe_id
    INTO v_player_id, v_universe_id
    FROM players p
    JOIN sectors s ON p.current_sector = s.id
    WHERE p.user_id = p_user_id;

    IF v_player_id IS NULL THEN
        RAISE EXCEPTION 'player_not_found' USING ERRCODE = 'P0001';
    END IF;

    -- Resolve target sector id in same universe
    SELECT id INTO v_sector_id FROM sectors WHERE universe_id = v_universe_id AND number = p_sector_number;
    IF v_sector_id IS NULL THEN
        RAISE EXCEPTION 'invalid_sector' USING ERRCODE = 'P0001';
    END IF;

    -- Must be in that sector
    IF NOT EXISTS (
        SELECT 1 FROM players p WHERE p.id = v_player_id AND p.current_sector = v_sector_id
    ) THEN
        RAISE EXCEPTION 'not_in_sector' USING ERRCODE = 'P0001';
    END IF;

    -- Sector must have a pre-generated unowned planet
    SELECT id INTO v_planet_id FROM planets WHERE sector_id = v_sector_id;
    IF v_planet_id IS NULL THEN
        RAISE EXCEPTION 'no_planet_in_sector' USING ERRCODE = 'P0001';
    END IF;

    -- Claim only if unowned
    UPDATE planets
    SET owner_player_id = v_player_id,
        name = COALESCE(NULLIF(TRIM(p_name), ''), 'Colony')
    WHERE id = v_planet_id AND owner_player_id IS NULL;

    -- Ensure we actually claimed it
    IF (SELECT owner_player_id FROM planets WHERE id = v_planet_id) IS DISTINCT FROM v_player_id THEN
        RAISE EXCEPTION 'planet_already_owned' USING ERRCODE = 'P0001';
    END IF;

    RETURN json_build_object(
        'planet_id', v_planet_id,
        'name', p_name,
        'sector_number', p_sector_number
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- Store resources on a planet
CREATE OR REPLACE FUNCTION game_planet_store(
    p_user_id UUID,
    p_planet UUID,
    p_resource TEXT,
    p_qty INT
)
RETURNS JSON AS $$
DECLARE
    v_player_id UUID;
    v_qty INT;
    v_field TEXT;
BEGIN
    IF p_qty IS NULL OR p_qty <= 0 THEN
        RAISE EXCEPTION 'invalid_qty' USING ERRCODE = 'P0001';
    END IF;

    SELECT id INTO v_player_id FROM players WHERE user_id = p_user_id;
    IF v_player_id IS NULL THEN RAISE EXCEPTION 'player_not_found' USING ERRCODE='P0001'; END IF;

    -- Ownership
    IF NOT EXISTS (SELECT 1 FROM planets WHERE id = p_planet AND owner_player_id = v_player_id) THEN
        RAISE EXCEPTION 'not_owner' USING ERRCODE='P0001';
    END IF;

    -- Map resource to field and ensure sufficient inventory
    IF p_resource NOT IN ('ore','organics','goods','energy') THEN
        RAISE EXCEPTION 'invalid_resource' USING ERRCODE='P0001';
    END IF;
    v_field := p_resource; -- matches column names

    -- Ensure player has enough
    IF (SELECT (CASE p_resource WHEN 'ore' THEN i.ore WHEN 'organics' THEN i.organics WHEN 'goods' THEN i.goods ELSE i.energy END)
        FROM inventories i WHERE i.player_id = v_player_id) < p_qty THEN
        RAISE EXCEPTION 'insufficient_inventory' USING ERRCODE='P0001';
    END IF;

    -- Move goods: decrement player inventory, increment planet stock
    EXECUTE format('UPDATE inventories SET %I = %I - $1 WHERE player_id = $2', v_field, v_field) USING p_qty, v_player_id;
    EXECUTE format('UPDATE planets SET %I = %I + $1 WHERE id = $2', v_field, v_field) USING p_qty, p_planet;

    RETURN (
        SELECT json_build_object(
            'player_inventory', json_build_object('ore', i.ore, 'organics', i.organics, 'goods', i.goods, 'energy', i.energy),
            'planet', json_build_object('id', pl.id, 'name', pl.name, 'ore', pl.ore, 'organics', pl.organics, 'goods', pl.goods, 'energy', pl.energy)
        )
        FROM inventories i CROSS JOIN planets pl
        WHERE i.player_id = v_player_id AND pl.id = p_planet
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- Withdraw resources from a planet
CREATE OR REPLACE FUNCTION game_planet_withdraw(
    p_user_id UUID,
    p_planet UUID,
    p_resource TEXT,
    p_qty INT
)
RETURNS JSON AS $$
DECLARE
    v_player_id UUID;
    v_field TEXT;
BEGIN
    IF p_qty IS NULL OR p_qty <= 0 THEN
        RAISE EXCEPTION 'invalid_qty' USING ERRCODE = 'P0001';
    END IF;

    SELECT id INTO v_player_id FROM players WHERE user_id = p_user_id;
    IF v_player_id IS NULL THEN RAISE EXCEPTION 'player_not_found' USING ERRCODE='P0001'; END IF;

    -- Ownership
    IF NOT EXISTS (SELECT 1 FROM planets WHERE id = p_planet AND owner_player_id = v_player_id) THEN
        RAISE EXCEPTION 'not_owner' USING ERRCODE='P0001';
    END IF;

    IF p_resource NOT IN ('ore','organics','goods','energy') THEN
        RAISE EXCEPTION 'invalid_resource' USING ERRCODE='P0001';
    END IF;
    v_field := p_resource;

    -- Ensure planet has enough
    IF (SELECT (CASE p_resource WHEN 'ore' THEN pl.ore WHEN 'organics' THEN pl.organics WHEN 'goods' THEN pl.goods ELSE pl.energy END)
        FROM planets pl WHERE pl.id = p_planet) < p_qty THEN
        RAISE EXCEPTION 'insufficient_planet_stock' USING ERRCODE='P0001';
    END IF;

    -- Move goods back to player
    EXECUTE format('UPDATE planets SET %I = %I - $1 WHERE id = $2', v_field, v_field) USING p_qty, p_planet;
    EXECUTE format('UPDATE inventories SET %I = %I + $1 WHERE player_id = $2', v_field, v_field) USING p_qty, v_player_id;

    RETURN (
        SELECT json_build_object(
            'player_inventory', json_build_object('ore', i.ore, 'organics', i.organics, 'goods', i.goods, 'energy', i.energy),
            'planet', json_build_object('id', pl.id, 'name', pl.name, 'ore', pl.ore, 'organics', pl.organics, 'goods', pl.goods, 'energy', pl.energy)
        )
        FROM inventories i CROSS JOIN planets pl
        WHERE i.player_id = v_player_id AND pl.id = p_planet
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


