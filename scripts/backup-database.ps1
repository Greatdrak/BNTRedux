# Database Backup Script for Quantum Nova Traders
# Creates comprehensive schema dump with all functions

$timestamp = Get-Date -Format "yyyy_MM_dd_HHmmss"
$backupDir = "sql_backups"
$backupFile = "$backupDir/complete_database_backup_$timestamp.sql"

# Create backup directory if it doesn't exist
if (!(Test-Path $backupDir)) {
    New-Item -ItemType Directory -Path $backupDir
}

Write-Host "Starting comprehensive database backup..." -ForegroundColor Green
Write-Host "Backup file: $backupFile" -ForegroundColor Cyan

# Get Supabase connection details from .env.local
$envContent = Get-Content ".env.local" -ErrorAction SilentlyContinue
$dbUrl = ""
$dbHost = ""
$dbName = ""
$dbUser = ""
$dbPassword = ""

foreach ($line in $envContent) {
    if ($line -match "^NEXT_PUBLIC_SUPABASE_URL=(.+)") {
        $dbUrl = $matches[1]
        # Extract host from URL
        if ($dbUrl -match "https://(.+)\.supabase\.co") {
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

if (-not $dbHost -or -not $dbPassword -or -not $dbName -or -not $dbUser) {
    Write-Host "Error: Could not find required database connection details in .env.local" -ForegroundColor Red
    Write-Host "Required: NEXT_PUBLIC_SUPABASE_URL, SUPABASE_DB_PASSWORD, SUPABASE_DB_NAME, SUPABASE_DB_USER" -ForegroundColor Red
    exit 1
}

Write-Host "Connecting to: $dbHost" -ForegroundColor Yellow
Write-Host "Database: $dbName" -ForegroundColor Yellow

# Create comprehensive pg_dump command
$pgDumpCmd = @"
pg_dump --host=$dbHost --port=5432 --username=$dbUser --dbname=$dbName --no-password --verbose --clean --if-exists --create --schema-only --no-owner --no-privileges --file="$backupFile"
"@

Write-Host "Executing pg_dump for schema..." -ForegroundColor Green
Write-Host "Command: $pgDumpCmd" -ForegroundColor Gray

# Set password environment variable and execute
$env:PGPASSWORD = $dbPassword
Invoke-Expression $pgDumpCmd

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Schema backup completed successfully!" -ForegroundColor Green
} else {
    Write-Host "❌ Schema backup failed!" -ForegroundColor Red
    exit 1
}

# Now get all functions
$functionsFile = "$backupDir/all_functions_$timestamp.sql"
Write-Host "Extracting all functions..." -ForegroundColor Green

$functionsCmd = @"
pg_dump --host=$dbHost --port=5432 --username=$dbUser --dbname=$dbName --no-password --verbose --functions-only --no-owner --no-privileges --file="$functionsFile"
"@

Invoke-Expression $functionsCmd

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Functions backup completed successfully!" -ForegroundColor Green
} else {
    Write-Host "❌ Functions backup failed!" -ForegroundColor Red
    exit 1
}

# Combine both files
$combinedFile = "$backupDir/complete_database_with_functions_$timestamp.sql"
Write-Host "Combining schema and functions..." -ForegroundColor Green

$combinedContent = @()
$combinedContent += "-- ================================================"
$combinedContent += "-- QUANTUM NOVA TRADERS - COMPLETE DATABASE BACKUP"
$combinedContent += "-- Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$combinedContent += "-- ================================================"
$combinedContent += ""
$combinedContent += "-- SCHEMA DUMP"
$combinedContent += "-- ================================================"
$combinedContent += Get-Content $backupFile -Raw
$combinedContent += ""
$combinedContent += "-- FUNCTIONS DUMP"
$combinedContent += "-- ================================================"
$combinedContent += Get-Content $functionsFile -Raw

$combinedContent | Out-File -FilePath $combinedFile -Encoding UTF8

Write-Host "✅ Combined backup created: $combinedFile" -ForegroundColor Green

# Get file sizes
$schemaSize = (Get-Item $backupFile).Length
$functionsSize = (Get-Item $functionsFile).Length
$combinedSize = (Get-Item $combinedFile).Length

Write-Host ""
Write-Host "📊 Backup Summary:" -ForegroundColor Cyan
$schemaSizeKB = [math]::Round($schemaSize/1KB, 2)
$functionsSizeKB = [math]::Round($functionsSize/1KB, 2)
$combinedSizeKB = [math]::Round($combinedSize/1KB, 2)
Write-Host "  Schema file: $backupFile ($schemaSizeKB KB)" -ForegroundColor White
Write-Host "  Functions file: $functionsFile ($functionsSizeKB KB)" -ForegroundColor White
Write-Host "  Combined file: $combinedFile ($combinedSizeKB KB)" -ForegroundColor White
Write-Host ""
Write-Host "🎯 Ready for manual SQL file archival!" -ForegroundColor Green
