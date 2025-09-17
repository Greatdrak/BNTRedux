-- STEP-BY-STEP Database Extraction
-- Run each section separately in Supabase SQL Editor
-- This avoids result limiting issues

-- ==============================================
-- STEP 1: TABLES ONLY
-- ==============================================

SELECT 
    'CREATE TABLE ' || t.table_name || ' (' || E'\n' ||
    string_agg(
        '    ' || c.column_name || ' ' || 
        CASE 
            WHEN c.data_type = 'character varying' THEN 'TEXT'
            WHEN c.data_type = 'character' THEN 'CHAR(' || c.character_maximum_length || ')'
            WHEN c.data_type = 'numeric' THEN 
                CASE 
                    WHEN c.numeric_precision IS NOT NULL AND c.numeric_scale IS NOT NULL THEN 
                        'NUMERIC(' || c.numeric_precision || ',' || c.numeric_scale || ')'
                    ELSE 'NUMERIC'
                END
            WHEN c.data_type = 'timestamp with time zone' THEN 'TIMESTAMPTZ'
            WHEN c.data_type = 'timestamp without time zone' THEN 'TIMESTAMP'
            WHEN c.data_type = 'time with time zone' THEN 'TIMETZ'
            WHEN c.data_type = 'time without time zone' THEN 'TIME'
            WHEN c.data_type = 'double precision' THEN 'DOUBLE PRECISION'
            WHEN c.data_type = 'real' THEN 'REAL'
            WHEN c.data_type = 'smallint' THEN 'SMALLINT'
            WHEN c.data_type = 'integer' THEN 'INTEGER'
            WHEN c.data_type = 'bigint' THEN 'BIGINT'
            WHEN c.data_type = 'boolean' THEN 'BOOLEAN'
            WHEN c.data_type = 'json' THEN 'JSON'
            WHEN c.data_type = 'jsonb' THEN 'JSONB'
            WHEN c.data_type = 'uuid' THEN 'UUID'
            WHEN c.data_type = 'bytea' THEN 'BYTEA'
            WHEN c.data_type = 'text' THEN 'TEXT'
            ELSE c.data_type
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
    ) || E'\n' || ');' as table_definition
FROM information_schema.tables t
JOIN information_schema.columns c ON t.table_name = c.table_name
WHERE t.table_schema = 'public' 
    AND t.table_type = 'BASE TABLE'
GROUP BY t.table_name
ORDER BY t.table_name;


