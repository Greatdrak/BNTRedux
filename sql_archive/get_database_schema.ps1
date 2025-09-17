# PowerShell script to extract complete database schema and functions
# This script uses the Supabase API to get everything without Docker

# Database connection details from Supabase CLI
$env:PGHOST = "aws-1-us-east-2.pooler.supabase.com"
$env:PGPORT = "5432"
$env:PGUSER = "cli_login_postgres.nczmmpqnzfwezskanvku"
$env:PGPASSWORD = "UorHiMUfYvhbyvdyryZlxTbeJMQpbHDJ"
$env:PGDATABASE = "postgres"

Write-Host "Extracting complete database schema and functions..."
Write-Host "Connection: $env:PGHOST:$env:PGPORT"
Write-Host "Database: $env:PGDATABASE"
Write-Host "User: $env:PGUSER"
Write-Host ""

# Create output file
$outputFile = "sql/complete_database_extraction_$(Get-Date -Format 'yyyy_MM_dd').sql"
New-Item -Path $outputFile -ItemType File -Force | Out-Null

# Add header
Add-Content -Path $outputFile -Value "-- Complete Database Extraction"
Add-Content -Path $outputFile -Value "-- Generated: $(Get-Date)"
Add-Content -Path $outputFile -Value "-- This file contains EVERYTHING needed to recreate the database"
Add-Content -Path $outputFile -Value "-- Connection: $env:PGHOST:$env:PGPORT"
Add-Content -Path $outputFile -Value ""

# SQL query to extract everything
$extractionQuery = @"
-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ==============================================
-- 1. ALL TABLES WITH COMPLETE DEFINITIONS
-- ==============================================

SELECT '-- Tables' as section_header;

-- Get table definitions with all details
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
    ) || E'\n' || ');' as table_sql
FROM information_schema.tables t
JOIN information_schema.columns c ON t.table_name = c.table_name
WHERE t.table_schema = 'public' 
    AND t.table_type = 'BASE TABLE'
GROUP BY t.table_name
ORDER BY t.table_name;

-- ==============================================
-- 2. ALL FUNCTIONS (RPCs) - COMPLETE DEFINITIONS
-- ==============================================

SELECT '-- Functions (RPCs)' as section_header;

SELECT 
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
    '$$;' as function_sql
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
JOIN pg_language l ON p.prolang = l.oid
WHERE n.nspname = 'public'
    AND p.prokind = 'f'
ORDER BY p.proname;

-- ==============================================
-- 3. ALL CONSTRAINTS
-- ==============================================

SELECT '-- Constraints' as section_header;

SELECT 
    'ALTER TABLE ' || tc.table_name || ' ADD CONSTRAINT ' || tc.constraint_name || ' ' ||
    CASE tc.constraint_type
        WHEN 'PRIMARY KEY' THEN 'PRIMARY KEY (' || string_agg(kcu.column_name, ', ') || ')'
        WHEN 'FOREIGN KEY' THEN 'FOREIGN KEY (' || string_agg(kcu.column_name, ', ') || ') REFERENCES ' || ccu.table_name || '(' || string_agg(ccu.column_name, ', ') || ')'
        WHEN 'UNIQUE' THEN 'UNIQUE (' || string_agg(kcu.column_name, ', ') || ')'
        WHEN 'CHECK' THEN 'CHECK (' || cc.check_clause || ')'
        ELSE tc.constraint_type
    END || ';' as constraint_sql
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

SELECT '-- Indexes' as section_header;

SELECT 
    'CREATE INDEX ' || indexname || ' ON ' || tablename || ' (' || 
    string_agg(attname, ', ') || ');' as index_sql
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

SELECT '-- Triggers' as section_header;

SELECT 
    'CREATE TRIGGER ' || trigger_name || E'\n' ||
    '    ' || action_timing || ' ' || event_manipulation || E'\n' ||
    '    ON ' || event_object_table || E'\n' ||
    '    FOR EACH ' || action_orientation || E'\n' ||
    '    EXECUTE FUNCTION ' || action_statement || ';' as trigger_sql
FROM information_schema.triggers
WHERE trigger_schema = 'public'
ORDER BY event_object_table, trigger_name;

-- ==============================================
-- 6. SUMMARY COUNT
-- ==============================================

SELECT '-- Summary' as summary_header;

SELECT 
    'Tables: ' || COUNT(*) as summary_info
FROM information_schema.tables 
WHERE table_schema = 'public' AND table_type = 'BASE TABLE'

UNION ALL

SELECT 'Functions: ' || COUNT(*) as summary_info
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public' AND p.prokind = 'f'

UNION ALL

SELECT 'Indexes: ' || COUNT(*) as summary_info
FROM pg_indexes 
WHERE schemaname = 'public'

UNION ALL

SELECT 'Triggers: ' || COUNT(*) as summary_info
FROM information_schema.triggers
WHERE trigger_schema = 'public';

-- ==============================================
-- END OF EXTRACTION
-- ==============================================

SELECT '-- End of complete database extraction' as end_marker;
"@

Write-Host "Executing extraction query..."
Write-Host "This may take a few minutes..."

# Execute the query and save to file
try {
    # Use psql if available, otherwise show instructions
    $psqlPath = Get-Command psql -ErrorAction SilentlyContinue
    if ($psqlPath) {
        Write-Host "Using psql to extract data..."
        $result = psql -c $extractionQuery
        Add-Content -Path $outputFile -Value $result
        Write-Host "Extraction complete!"
    } else {
        Write-Host "psql not found. Please install PostgreSQL client tools."
        Write-Host "You can download from: https://www.postgresql.org/download/windows/"
        Write-Host ""
        Write-Host "Alternative: Use the Supabase SQL Editor to run this query:"
        Write-Host "1. Go to your Supabase project dashboard"
        Write-Host "2. Open SQL Editor"
        Write-Host "3. Copy and paste the query from: $outputFile"
        Write-Host "4. Run the query and save the results"
        
        # Save the query to file for manual execution
        Add-Content -Path $outputFile -Value $extractionQuery
    }
} catch {
    Write-Host "Error: $($_.Exception.Message)"
    Write-Host "Please check your connection details and try again."
}

Write-Host ""
Write-Host "Output saved to: $outputFile"
Write-Host ""
Write-Host "To get the complete database dump with data, you need to:"
Write-Host "1. Install Docker Desktop"
Write-Host "2. Run: .\supabase.exe db dump --file sql/complete_database_dump.sql"
Write-Host ""
Write-Host "Or install PostgreSQL client tools and use pg_dump directly."


