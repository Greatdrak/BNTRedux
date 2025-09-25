# Database Backup Script using Supabase CLI Docker
# Creates comprehensive schema dump with all functions

$timestamp = Get-Date -Format "yyyy_MM_dd_HHmmss"
$backupDir = "sql_backups"
$schemaFile = "$backupDir/complete_schema_dump_$timestamp.sql"
$functionsFile = "$backupDir/all_functions_dump_$timestamp.sql"
$combinedFile = "$backupDir/complete_database_with_functions_$timestamp.sql"

# Create backup directory if it doesn't exist
if (!(Test-Path $backupDir)) {
    New-Item -ItemType Directory -Path $backupDir
}

Write-Host "Starting comprehensive database backup using Supabase CLI Docker..." -ForegroundColor Green
Write-Host "Backup directory: $backupDir" -ForegroundColor Cyan

# Check if Docker is running
try {
    docker --version 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Docker not found"
    }
    Write-Host "✅ Docker found" -ForegroundColor Green
} catch {
    Write-Host "❌ Docker not found or not running. Please start Docker Desktop." -ForegroundColor Red
    exit 1
}

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

# Pull the latest Supabase CLI Docker image
Write-Host ""
Write-Host "📥 Pulling Supabase CLI Docker image..." -ForegroundColor Cyan
docker pull supabase/cli:latest

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Failed to pull Supabase CLI Docker image!" -ForegroundColor Red
    exit 1
}

Write-Host "✅ Supabase CLI Docker image ready" -ForegroundColor Green

# Create a temporary container to run the backup
$containerName = "supabase-backup-$timestamp"

Write-Host ""
Write-Host "📋 Creating schema dump..." -ForegroundColor Cyan

# Run schema dump
docker run --rm --name $containerName `
    -e PGPASSWORD=$dbPassword `
    -v "${PWD}\$backupDir:/backup" `
    supabase/cli:latest `
    pg_dump --host=$dbHost --port=5432 --username=$dbUser --dbname=$dbName --schema-only --file=/backup/$(Split-Path $schemaFile -Leaf)

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Schema dump completed: $schemaFile" -ForegroundColor Green
} else {
    Write-Host "❌ Schema dump failed!" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "🔧 Creating functions dump..." -ForegroundColor Cyan

# Run functions dump
docker run --rm --name $containerName `
    -e PGPASSWORD=$dbPassword `
    -v "${PWD}\$backupDir:/backup" `
    supabase/cli:latest `
    pg_dump --host=$dbHost --port=5432 --username=$dbUser --dbname=$dbName --functions-only --file=/backup/$(Split-Path $functionsFile -Leaf)

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Functions dump completed: $functionsFile" -ForegroundColor Green
} else {
    Write-Host "❌ Functions dump failed!" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "🔗 Combining schema and functions..." -ForegroundColor Cyan

# Combine both files
$combinedContent = @()
$combinedContent += "-- ================================================"
$combinedContent += "-- QUANTUM NOVA TRADERS - COMPLETE DATABASE BACKUP"
$combinedContent += "-- Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$combinedContent += "-- Schema + Functions Dump via Docker"
$combinedContent += "-- ================================================"
$combinedContent += ""
$combinedContent += "-- SCHEMA DUMP"
$combinedContent += "-- ================================================"
$combinedContent += Get-Content $schemaFile -Raw
$combinedContent += ""
$combinedContent += "-- FUNCTIONS DUMP"
$combinedContent += "-- ================================================"
$combinedContent += Get-Content $functionsFile -Raw

$combinedContent | Out-File -FilePath $combinedFile -Encoding UTF8

Write-Host "✅ Combined backup created: $combinedFile" -ForegroundColor Green

# Get file sizes
$schemaSize = (Get-Item $schemaFile).Length
$functionsSize = (Get-Item $functionsFile).Length
$combinedSize = (Get-Item $combinedFile).Length

Write-Host ""
Write-Host "📊 Backup Summary:" -ForegroundColor Cyan
$schemaSizeKB = [math]::Round($schemaSize/1KB, 2)
$functionsSizeKB = [math]::Round($functionsSize/1KB, 2)
$combinedSizeKB = [math]::Round($combinedSize/1KB, 2)
Write-Host "  Schema file: $schemaFile ($schemaSizeKB KB)" -ForegroundColor White
Write-Host "  Functions file: $functionsFile ($functionsSizeKB KB)" -ForegroundColor White
Write-Host "  Combined file: $combinedFile ($combinedSizeKB KB)" -ForegroundColor White
Write-Host ""
Write-Host "🎯 Files ready for manual SQL file archival!" -ForegroundColor Green
Write-Host "💡 You can now move the SQL files from the sql/ directory to sql_archive/" -ForegroundColor Yellow
