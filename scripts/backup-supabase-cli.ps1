# Database Backup using Supabase CLI
$timestamp = Get-Date -Format "yyyy_MM_dd_HHmmss"
$backupDir = "sql_backups"

if (!(Test-Path $backupDir)) {
    New-Item -ItemType Directory -Path $backupDir
}

Write-Host "Starting database backup using Supabase CLI..." -ForegroundColor Green

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

Write-Host "Connecting to: $dbHost" -ForegroundColor Yellow
Write-Host "Database: $dbName" -ForegroundColor Yellow

# Create connection string
$connectionString = "postgresql://$dbUser`:$dbPassword@$dbHost`:5432/$dbName"
$encodedConnectionString = [System.Web.HttpUtility]::UrlEncode($connectionString)

# Schema dump
Write-Host "Creating schema dump..." -ForegroundColor Cyan
$schemaFile = "complete_schema_dump_$timestamp.sql"
.\supabase.exe db dump --db-url $encodedConnectionString --file "$backupDir/$schemaFile"

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Schema dump completed" -ForegroundColor Green
} else {
    Write-Host "❌ Schema dump failed" -ForegroundColor Red
}

# Functions dump (schema-only with functions)
Write-Host "Creating functions dump..." -ForegroundColor Cyan
$functionsFile = "all_functions_dump_$timestamp.sql"
.\supabase.exe db dump --db-url $encodedConnectionString --schema-only --file "$backupDir/$functionsFile"

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Functions dump completed" -ForegroundColor Green
} else {
    Write-Host "❌ Functions dump failed" -ForegroundColor Red
}

Write-Host ""
Write-Host "🎯 Backup completed!" -ForegroundColor Green
Write-Host "Files created in: $backupDir" -ForegroundColor Cyan

# List created files
Get-ChildItem $backupDir -Filter "*$timestamp*" | ForEach-Object {
    $sizeKB = [math]::Round($_.Length/1KB, 2)
    Write-Host "  $($_.Name) ($sizeKB KB)" -ForegroundColor White
}
