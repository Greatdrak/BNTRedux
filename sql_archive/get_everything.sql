-- Get EVERYTHING from the database
-- Run this in Supabase SQL Editor to extract complete schema and functions

-- ==============================================
-- 1. ALL TABLE DEFINITIONS
-- ==============================================

SELECT 
    '-- Table: ' || t.table_name as comment,
    'CREATE TABLE ' || t.table_name || ' (' || E'\n' ||
    string_agg(
        '    ' || c.column_name || ' ' || c.data_type || 
        CASE 
            WHEN c.character_maximum_length IS NOT NULL THEN '(' || c.character_maximum_length || ')'
            ELSE ''
        END ||
        CASE 
            WHEN c.is_nullable = 'NO' THEN ' NOT NULL'
            ELSE ''
        END ||
        CASE 
            WHEN c.column_default IS NOT NULL THEN ' DEFAULT ' || c.column_default
            ELSE ''
        END,
        ',' || E'\n'
    ) || E'\n' || ');' as sql_statement
FROM information_schema.tables t
JOIN information_schema.columns c ON t.table_name = c.table_name
WHERE t.table_schema = 'public' 
    AND t.table_type = 'BASE TABLE'
GROUP BY t.table_name
ORDER BY t.table_name;

-- ==============================================
-- 2. ALL FUNCTIONS (RPCs)
-- ==============================================

SELECT 
    '-- Function: ' || p.proname as comment,
    'CREATE OR REPLACE FUNCTION ' || p.proname || '(' ||
    pg_get_function_arguments(p.oid) || ')' || E'\n' ||
    'RETURNS ' || pg_get_function_result(p.oid) || E'\n' ||
    'LANGUAGE ' || l.lanname || E'\n' ||
    CASE 
        WHEN p.prosecdef THEN 'SECURITY DEFINER' || E'\n'
        ELSE ''
    END ||
    'AS $$' || E'\n' ||
    p.prosrc || E'\n' ||
    '$$;' as sql_statement
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
JOIN pg_language l ON p.prolang = l.oid
WHERE n.nspname = 'public'
    AND p.prokind = 'f'
ORDER BY p.proname;

-- ==============================================
-- 3. ALL CONSTRAINTS
-- ==============================================

SELECT 
    '-- Constraint: ' || tc.constraint_name as comment,
    'ALTER TABLE ' || tc.table_name || ' ADD CONSTRAINT ' || tc.constraint_name || ' ' ||
    CASE tc.constraint_type
        WHEN 'PRIMARY KEY' THEN 'PRIMARY KEY (' || string_agg(kcu.column_name, ', ') || ')'
        WHEN 'FOREIGN KEY' THEN 'FOREIGN KEY (' || string_agg(kcu.column_name, ', ') || ') REFERENCES ' || ccu.table_name || '(' || string_agg(ccu.column_name, ', ') || ')'
        WHEN 'UNIQUE' THEN 'UNIQUE (' || string_agg(kcu.column_name, ', ') || ')'
        WHEN 'CHECK' THEN 'CHECK (' || cc.check_clause || ')'
        ELSE tc.constraint_type
    END || ';' as sql_statement
FROM information_schema.table_constraints tc
LEFT JOIN information_schema.key_column_usage kcu ON tc.constraint_name = kcu.constraint_name
LEFT JOIN information_schema.constraint_column_usage ccu ON tc.constraint_name = ccu.constraint_name
LEFT JOIN information_schema.check_constraints cc ON tc.constraint_name = cc.constraint_name
WHERE tc.table_schema = 'public'
GROUP BY tc.table_name, tc.constraint_name, tc.constraint_type, cc.check_clause
ORDER BY tc.table_name, tc.constraint_name;

-- ==============================================
-- 4. ALL INDEXES
-- ==============================================

SELECT 
    '-- Index: ' || indexname as comment,
    'CREATE INDEX ' || indexname || ' ON ' || tablename || ' (' || 
    string_agg(attname, ', ') || ');' as sql_statement
FROM pg_indexes pi
JOIN pg_class c ON c.relname = pi.indexname
JOIN pg_index i ON i.indexrelid = c.oid
JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY(i.indkey)
WHERE schemaname = 'public'
GROUP BY indexname, tablename
ORDER BY tablename, indexname;

-- ==============================================
-- 5. ALL TRIGGERS
-- ==============================================

SELECT 
    '-- Trigger: ' || trigger_name as comment,
    'CREATE TRIGGER ' || trigger_name || E'\n' ||
    '    ' || action_timing || ' ' || event_manipulation || E'\n' ||
    '    ON ' || event_object_table || E'\n' ||
    '    FOR EACH ' || action_orientation || E'\n' ||
    '    EXECUTE FUNCTION ' || action_statement || ';' as sql_statement
FROM information_schema.triggers
WHERE trigger_schema = 'public'
ORDER BY event_object_table, trigger_name;

-- ==============================================
-- 6. SUMMARY COUNT
-- ==============================================

SELECT 'SUMMARY:' as summary_type, 
       'Tables: ' || COUNT(*) as count_info
FROM information_schema.tables 
WHERE table_schema = 'public' AND table_type = 'BASE TABLE'

UNION ALL

SELECT 'Functions: ' || COUNT(*) as count_info
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public' AND p.prokind = 'f'

UNION ALL

SELECT 'Indexes: ' || COUNT(*) as count_info
FROM pg_indexes 
WHERE schemaname = 'public'

UNION ALL

SELECT 'Triggers: ' || COUNT(*) as count_info
FROM information_schema.triggers
WHERE trigger_schema = 'public';


