# Database Backup Script using Supabase CLI
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

Write-Host "Starting comprehensive database backup using Supabase CLI..." -ForegroundColor Green
Write-Host "Backup directory: $backupDir" -ForegroundColor Cyan

# Check if Supabase CLI is installed
try {
    $supabaseVersion = supabase --version 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "Supabase CLI not found"
    }
    Write-Host "✅ Supabase CLI found: $supabaseVersion" -ForegroundColor Green
} catch {
    Write-Host "❌ Supabase CLI not found. Please install it first:" -ForegroundColor Red
    Write-Host "   npm install -g supabase" -ForegroundColor Yellow
    Write-Host "   or visit: https://supabase.com/docs/guides/cli" -ForegroundColor Yellow
    exit 1
}

# Check if project is linked
try {
    $projectInfo = supabase status 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "Project not linked"
    }
    Write-Host "✅ Supabase project is linked" -ForegroundColor Green
} catch {
    Write-Host "❌ Supabase project not linked. Please run:" -ForegroundColor Red
    Write-Host "   supabase login" -ForegroundColor Yellow
    Write-Host "   supabase link --project-ref YOUR_PROJECT_REF" -ForegroundColor Yellow
    exit 1
}

Write-Host ""
Write-Host "📋 Creating schema dump..." -ForegroundColor Cyan
Write-Host "Command: supabase db dump --schema-only --file $schemaFile" -ForegroundColor Gray

# Create schema dump
supabase db dump --schema-only --file $schemaFile

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Schema dump completed: $schemaFile" -ForegroundColor Green
} else {
    Write-Host "❌ Schema dump failed!" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "🔧 Creating functions dump..." -ForegroundColor Cyan
Write-Host "Command: supabase db dump --data-only=false --functions-only --file $functionsFile" -ForegroundColor Gray

# Create functions dump
supabase db dump --data-only=false --functions-only --file $functionsFile

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
$combinedContent += "-- Schema + Functions Dump"
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
