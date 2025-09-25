# Database Backup using PostgreSQL Docker image
$timestamp = Get-Date -Format "yyyy_MM_dd_HHmmss"
$backupDir = "sql_backups"

if (!(Test-Path $backupDir)) {
    New-Item -ItemType Directory -Path $backupDir
}

Write-Host "Starting database backup using PostgreSQL Docker..." -ForegroundColor Green

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
Write-Host "Database: $dbName" -ForegroundColor Yellow

# Pull PostgreSQL image
Write-Host "Pulling PostgreSQL Docker image..." -ForegroundColor Cyan
docker pull postgres:15

# Schema dump
Write-Host "Creating schema dump..." -ForegroundColor Cyan
$schemaFile = "complete_schema_dump_$timestamp.sql"
docker run --rm -e PGPASSWORD=$dbPassword -v "${backupPath}:/backup" postgres:15 pg_dump --host=$dbHost --port=5432 --username=$dbUser --dbname=$dbName --schema-only --file="/backup/$schemaFile"

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Schema dump completed" -ForegroundColor Green
} else {
    Write-Host "❌ Schema dump failed" -ForegroundColor Red
}

# Functions dump  
Write-Host "Creating functions dump..." -ForegroundColor Cyan
$functionsFile = "all_functions_dump_$timestamp.sql"
docker run --rm -e PGPASSWORD=$dbPassword -v "${backupPath}:/backup" postgres:15 pg_dump --host=$dbHost --port=5432 --username=$dbUser --dbname=$dbName --functions-only --file="/backup/$functionsFile"

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Functions dump completed" -ForegroundColor Green
} else {
    Write-Host "❌ Functions dump failed" -ForegroundColor Red
}

# Combined dump
Write-Host "Creating combined dump..." -ForegroundColor Cyan
$combinedFile = "complete_database_with_functions_$timestamp.sql"
docker run --rm -e PGPASSWORD=$dbPassword -v "${backupPath}:/backup" postgres:15 pg_dump --host=$dbHost --port=5432 --username=$dbUser --dbname=$dbName --schema-only --functions-only --file="/backup/$combinedFile"

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Combined dump completed" -ForegroundColor Green
} else {
    Write-Host "❌ Combined dump failed" -ForegroundColor Red
}

Write-Host ""
Write-Host "🎯 Backup completed!" -ForegroundColor Green
Write-Host "Files created in: $backupPath" -ForegroundColor Cyan

# List created files
Get-ChildItem $backupPath -Filter "*$timestamp*" | ForEach-Object {
    $sizeKB = [math]::Round($_.Length/1KB, 2)
    Write-Host "  $($_.Name) ($sizeKB KB)" -ForegroundColor White
}
