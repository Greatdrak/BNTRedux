-- Complete Database Extraction Script
-- Run this in Supabase SQL Editor to get EVERYTHING: schema, functions, data, etc.
-- This creates a comprehensive dump that can recreate the entire database

-- ==============================================
-- SCHEMA EXTRACTION
-- ==============================================

-- Extract all table definitions
SELECT 
    'CREATE TABLE ' || schemaname || '.' || tablename || ' (' || E'\n' ||
    string_agg(
        '    ' || column_name || ' ' || data_type || 
        CASE 
            WHEN character_maximum_length IS NOT NULL THEN '(' || character_maximum_length || ')'
            ELSE ''
        END ||
        CASE 
            WHEN is_nullable = 'NO' THEN ' NOT NULL'
            ELSE ''
        END ||
        CASE 
            WHEN column_default IS NOT NULL THEN ' DEFAULT ' || column_default
            ELSE ''
        END,
        ',' || E'\n'
    ) || E'\n' || ');' as table_definition
FROM information_schema.tables t
JOIN information_schema.columns c ON t.table_name = c.table_name
WHERE t.table_schema = 'public' 
    AND t.table_type = 'BASE TABLE'
GROUP BY schemaname, tablename
ORDER BY tablename;

-- Extract all constraints
SELECT 
    'ALTER TABLE ' || tc.table_name || ' ADD CONSTRAINT ' || tc.constraint_name || ' ' ||
    CASE tc.constraint_type
        WHEN 'PRIMARY KEY' THEN 'PRIMARY KEY (' || string_agg(kcu.column_name, ', ') || ')'
        WHEN 'FOREIGN KEY' THEN 'FOREIGN KEY (' || string_agg(kcu.column_name, ', ') || ') REFERENCES ' || ccu.table_name || '(' || string_agg(ccu.column_name, ', ') || ')'
        WHEN 'UNIQUE' THEN 'UNIQUE (' || string_agg(kcu.column_name, ', ') || ')'
        WHEN 'CHECK' THEN 'CHECK (' || cc.check_clause || ')'
        ELSE tc.constraint_type
    END || ';' as constraint_definition
FROM information_schema.table_constraints tc
LEFT JOIN information_schema.key_column_usage kcu ON tc.constraint_name = kcu.constraint_name
LEFT JOIN information_schema.constraint_column_usage ccu ON tc.constraint_name = ccu.constraint_name
LEFT JOIN information_schema.check_constraints cc ON tc.constraint_name = cc.constraint_name
WHERE tc.table_schema = 'public'
GROUP BY tc.table_name, tc.constraint_name, tc.constraint_type, cc.check_clause
ORDER BY tc.table_name, tc.constraint_name;

-- Extract all indexes
SELECT 
    'CREATE INDEX ' || indexname || ' ON ' || tablename || ' (' || 
    string_agg(attname, ', ') || ');' as index_definition
FROM pg_indexes pi
JOIN pg_class c ON c.relname = pi.indexname
JOIN pg_index i ON i.indexrelid = c.oid
JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY(i.indkey)
WHERE schemaname = 'public'
GROUP BY indexname, tablename
ORDER BY tablename, indexname;

-- ==============================================
-- FUNCTION EXTRACTION
-- ==============================================

-- Extract all functions
SELECT 
    'CREATE OR REPLACE FUNCTION ' || n.nspname || '.' || p.proname || '(' ||
    pg_get_function_arguments(p.oid) || ')' || E'\n' ||
    'RETURNS ' || pg_get_function_result(p.oid) || E'\n' ||
    'LANGUAGE ' || l.lanname || E'\n' ||
    CASE 
        WHEN p.prosecdef THEN 'SECURITY DEFINER' || E'\n'
        ELSE ''
    END ||
    'AS $$' || E'\n' ||
    p.prosrc || E'\n' ||
    '$$;' as function_definition
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
JOIN pg_language l ON p.prolang = l.oid
WHERE n.nspname = 'public'
    AND p.prokind = 'f'  -- functions only, not procedures
ORDER BY p.proname;

-- ==============================================
-- DATA EXTRACTION
-- ==============================================

-- Extract all data from each table
DO $$
DECLARE
    table_name TEXT;
    column_list TEXT;
    insert_sql TEXT;
BEGIN
    FOR table_name IN 
        SELECT tablename 
        FROM pg_tables 
        WHERE schemaname = 'public' 
        ORDER BY tablename
    LOOP
        -- Get column list
        SELECT string_agg(column_name, ', ')
        INTO column_list
        FROM information_schema.columns
        WHERE table_name = table_name
        AND table_schema = 'public';
        
        -- Generate INSERT statements
        insert_sql := 'INSERT INTO ' || table_name || ' (' || column_list || ') VALUES' || E'\n';
        
        RAISE NOTICE 'Table: %', table_name;
        RAISE NOTICE 'Columns: %', column_list;
        RAISE NOTICE 'SQL: %', insert_sql;
    END LOOP;
END $$;

-- ==============================================
-- TRIGGER EXTRACTION
-- ==============================================

-- Extract all triggers
SELECT 
    'CREATE TRIGGER ' || trigger_name || E'\n' ||
    '    ' || action_timing || ' ' || event_manipulation || E'\n' ||
    '    ON ' || event_object_table || E'\n' ||
    '    FOR EACH ' || action_orientation || E'\n' ||
    '    EXECUTE FUNCTION ' || action_statement || ';' as trigger_definition
FROM information_schema.triggers
WHERE trigger_schema = 'public'
ORDER BY event_object_table, trigger_name;

-- ==============================================
-- SEQUENCE EXTRACTION
-- ==============================================

-- Extract all sequences
SELECT 
    'CREATE SEQUENCE ' || sequence_name || E'\n' ||
    '    START WITH ' || start_value || E'\n' ||
    '    INCREMENT BY ' || increment || E'\n' ||
    '    MINVALUE ' || minimum_value || E'\n' ||
    '    MAXVALUE ' || maximum_value || E'\n' ||
    '    CACHE ' || cache_size || ';' as sequence_definition
FROM information_schema.sequences
WHERE sequence_schema = 'public'
ORDER BY sequence_name;

-- ==============================================
-- VIEW EXTRACTION
-- ==============================================

-- Extract all views
SELECT 
    'CREATE VIEW ' || table_name || ' AS' || E'\n' ||
    view_definition || ';' as view_definition
FROM information_schema.views
WHERE table_schema = 'public'
ORDER BY table_name;

-- ==============================================
-- SUMMARY REPORT
-- ==============================================

-- Generate summary of what we found
SELECT 
    'DATABASE EXTRACTION SUMMARY' as report_type,
    'Tables: ' || COUNT(*) as table_count
FROM information_schema.tables 
WHERE table_schema = 'public' AND table_type = 'BASE TABLE'

UNION ALL

SELECT 
    'Functions: ' || COUNT(*) as function_count
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public' AND p.prokind = 'f'

UNION ALL

SELECT 
    'Indexes: ' || COUNT(*) as index_count
FROM pg_indexes 
WHERE schemaname = 'public'

UNION ALL

SELECT 
    'Triggers: ' || COUNT(*) as trigger_count
FROM information_schema.triggers
WHERE trigger_schema = 'public';

-- ==============================================
-- COMPLETE RECREATION SCRIPT GENERATION
-- ==============================================

-- This will generate a complete recreation script
SELECT '-- Complete Database Recreation Script' as script_header
UNION ALL
SELECT '-- Generated on: ' || NOW()::TEXT as generation_time
UNION ALL
SELECT '-- Run this script to recreate the entire database from scratch' as instructions;


