# Simple Docker-based Database Backup
$timestamp = Get-Date -Format "yyyy_MM_dd_HHmmss"
$backupDir = "sql_backups"

if (!(Test-Path $backupDir)) {
    New-Item -ItemType Directory -Path $backupDir
}

Write-Host "Starting database backup using Docker..." -ForegroundColor Green

# Get database connection details
$envContent = Get-Content ".env.local"
$dbHost = ""
$dbPassword = ""
$dbName = ""
$dbUser = ""

foreach ($line in $envContent) {
    if ($line -match "^NEXT_PUBLIC_SUPABASE_URL=(.+)") {
        if ($line -match "https://(.+)\.supabase\.co") {
            $dbHost = "$($matches[1]).supabase.co"
        }
    }
    if ($line -match "^SUPABASE_DB_PASSWORD=(.+)") {
        $dbPassword = $matches[1]
    }
    if ($line -match "^SUPABASE_DB_NAME=(.+)") {
        $dbName = $matches[1]
    }
    if ($line -match "^SUPABASE_DB_USER=(.+)") {
        $dbUser = $matches[1]
    }
}

$currentPath = Get-Location
$backupPath = Join-Path $currentPath $backupDir

Write-Host "Connecting to: $dbHost" -ForegroundColor Yellow

# Pull Supabase CLI image
Write-Host "Pulling Supabase CLI image..." -ForegroundColor Cyan
docker pull supabase/cli:latest

# Schema dump
Write-Host "Creating schema dump..." -ForegroundColor Cyan
$schemaFile = "complete_schema_dump_$timestamp.sql"
docker run --rm -e PGPASSWORD=$dbPassword -v "${backupPath}:/backup" supabase/cli:latest pg_dump --host=$dbHost --port=5432 --username=$dbUser --dbname=$dbName --schema-only --file="/backup/$schemaFile"

# Functions dump  
Write-Host "Creating functions dump..." -ForegroundColor Cyan
$functionsFile = "all_functions_dump_$timestamp.sql"
docker run --rm -e PGPASSWORD=$dbPassword -v "${backupPath}:/backup" supabase/cli:latest pg_dump --host=$dbHost --port=5432 --username=$dbUser --dbname=$dbName --functions-only --file="/backup/$functionsFile"

Write-Host "✅ Backup completed!" -ForegroundColor Green
Write-Host "Files created in: $backupPath" -ForegroundColor Cyan
