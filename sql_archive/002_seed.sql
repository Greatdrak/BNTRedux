-- BNT Redux Seed Data
-- How to apply: Run this file once in Supabase SQL Editor after running 001_init.sql
-- This creates one playable universe with 500 sectors, warps, and ports

-- Check if universe already exists to prevent duplication
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM universes WHERE name = 'Alpha') THEN
        RAISE NOTICE 'Universe Alpha already exists, skipping seed data';
        RETURN;
    END IF;
END $$;

-- Create the Alpha universe
INSERT INTO universes (name, sector_count) VALUES ('Alpha', 500);

-- Get the universe ID for reference
DO $$
DECLARE
    universe_uuid UUID;
    sector_uuid UUID;
    port_count INTEGER := 0;
    target_ports INTEGER := 50; -- ~10% of 500 sectors
    warp_count INTEGER;
    target_sector INTEGER;
    existing_warps INTEGER;
BEGIN
    -- Get the universe ID
    SELECT id INTO universe_uuid FROM universes WHERE name = 'Alpha';
    
    -- Create 500 sectors
    FOR i IN 1..500 LOOP
        INSERT INTO sectors (universe_id, number) 
        VALUES (universe_uuid, i);
    END LOOP;
    
    -- Create warps: 1-3 bidirectional connections per sector
    FOR i IN 1..500 LOOP
        -- Get current sector ID
        SELECT id INTO sector_uuid FROM sectors 
        WHERE universe_id = universe_uuid AND number = i;
        
        -- Determine number of warps for this sector (1-3)
        warp_count := 1 + (random() * 2)::INTEGER;
        
        -- Create warps to other sectors
        FOR j IN 1..warp_count LOOP
            LOOP
                -- Pick a random target sector (not self)
                target_sector := 1 + (random() * 499)::INTEGER;
                IF target_sector >= i THEN
                    target_sector := target_sector + 1;
                END IF;
                
                -- Check if warp already exists
                SELECT COUNT(*) INTO existing_warps
                FROM warps w
                JOIN sectors s1 ON w.from_sector = s1.id
                JOIN sectors s2 ON w.to_sector = s2.id
                WHERE w.universe_id = universe_uuid 
                AND s1.number = i 
                AND s2.number = target_sector;
                
                -- If no existing warp, create it
                IF existing_warps = 0 THEN
                    INSERT INTO warps (universe_id, from_sector, to_sector)
                    SELECT universe_uuid, s1.id, s2.id
                    FROM sectors s1, sectors s2
                    WHERE s1.universe_id = universe_uuid AND s1.number = i
                    AND s2.universe_id = universe_uuid AND s2.number = target_sector;
                    
                    -- Create reverse warp (bidirectional)
                    INSERT INTO warps (universe_id, from_sector, to_sector)
                    SELECT universe_uuid, s2.id, s1.id
                    FROM sectors s1, sectors s2
                    WHERE s1.universe_id = universe_uuid AND s1.number = i
                    AND s2.universe_id = universe_uuid AND s2.number = target_sector;
                    
                    EXIT; -- Exit the inner loop, move to next warp
                END IF;
            END LOOP;
        END LOOP;
    END LOOP;
    
    -- Create ports on ~10% of sectors (random selection)
    FOR i IN 1..500 LOOP
        -- 10% chance for each sector to have a port
        IF random() < 0.1 THEN
            SELECT id INTO sector_uuid FROM sectors 
            WHERE universe_id = universe_uuid AND number = i;
            
            INSERT INTO ports (sector_id, kind, ore, organics, goods, energy, 
                             price_ore, price_organics, price_goods, price_energy)
            VALUES (
                sector_uuid,
                'trade',
                -- Stock: small positive amounts
                (10 + random() * 40)::INTEGER,  -- ore: 10-50
                (5 + random() * 25)::INTEGER,  -- organics: 5-30
                (2 + random() * 18)::INTEGER,  -- goods: 2-20
                (20 + random() * 80)::INTEGER, -- energy: 20-100
                -- Prices: energy cheapest, goods most expensive
                8.0 + random() * 4.0,   -- ore: 8-12
                12.0 + random() * 6.0,   -- organics: 12-18
                20.0 + random() * 10.0,  -- goods: 20-30
                3.0 + random() * 4.0     -- energy: 3-7
            );
            
            port_count := port_count + 1;
        END IF;
    END LOOP;
    
    RAISE NOTICE 'Created universe Alpha with 500 sectors and % ports', port_count;
END $$;
