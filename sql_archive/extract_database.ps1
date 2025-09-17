# PowerShell script to extract complete database schema and functions
# This script connects directly to Supabase and extracts everything

# Database connection details from Supabase CLI
$env:PGHOST = "aws-1-us-east-2.pooler.supabase.com"
$env:PGPORT = "5432"
$env:PGUSER = "cli_login_postgres.nczmmpqnzfwezskanvku"
$env:PGPASSWORD = "sVdMnuAQBBDVfsrwbyGegtepROtQrjTC"
$env:PGDATABASE = "postgres"

# Check if psql is available
$psqlPath = Get-Command psql -ErrorAction SilentlyContinue
if (-not $psqlPath) {
    Write-Host "psql not found. Please install PostgreSQL client tools."
    Write-Host "You can download from: https://www.postgresql.org/download/windows/"
    exit 1
}

Write-Host "Extracting complete database schema and functions..."

# Create output file
$outputFile = "sql/complete_database_extraction.sql"
New-Item -Path $outputFile -ItemType File -Force | Out-Null

# Add header
Add-Content -Path $outputFile -Value "-- Complete Database Extraction"
Add-Content -Path $outputFile -Value "-- Generated: $(Get-Date)"
Add-Content -Path $outputFile -Value "-- This file contains EVERYTHING needed to recreate the database"
Add-Content -Path $outputFile -Value ""

# Extract schema only (tables, functions, etc.)
Write-Host "Extracting schema..."
$schemaQuery = @"
-- Schema extraction
SELECT '-- Tables' as section;
SELECT 'CREATE TABLE IF NOT EXISTS ' || schemaname || '.' || tablename || ' (' || E'\n' ||
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
) || E'\n' || ');' as sql_statement
FROM information_schema.tables t
JOIN information_schema.columns c ON t.table_name = c.table_name
WHERE t.table_schema = 'public' 
    AND t.table_type = 'BASE TABLE'
GROUP BY schemaname, tablename
ORDER BY tablename;

-- Functions extraction
SELECT '-- Functions' as section;
SELECT 'CREATE OR REPLACE FUNCTION ' || p.proname || '(' ||
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
"@

# Execute the query and save to file
$schemaResult = psql -c $schemaQuery
Add-Content -Path $outputFile -Value $schemaResult

Write-Host "Schema extraction complete!"
Write-Host "Output saved to: $outputFile"
Write-Host ""
Write-Host "To get the complete database dump, you need to:"
Write-Host "1. Install Docker Desktop"
Write-Host "2. Run: .\supabase.exe db dump --file sql/complete_database_dump.sql"
Write-Host ""
Write-Host "Or install PostgreSQL client tools and use pg_dump directly."


