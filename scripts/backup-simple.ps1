# Simple Database Backup using Supabase CLI
$timestamp = Get-Date -Format "yyyy_MM_dd_HHmmss"
$backupDir = "sql_backups"

if (!(Test-Path $backupDir)) {
    New-Item -ItemType Directory -Path $backupDir
}

Write-Host "Starting database backup..." -ForegroundColor Green

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

# Create connection string and URL encode manually
$connectionString = "postgresql://$dbUser`:$dbPassword@$dbHost`:5432/$dbName"
$encodedConnectionString = $connectionString -replace ':', '%3A' -replace '/', '%2F' -replace '@', '%40'

Write-Host "Creating schema dump..." -ForegroundColor Cyan
$schemaFile = "complete_schema_dump_$timestamp.sql"

# Use the --db-url flag with proper formatting
.\supabase.exe db dump --db-url "$encodedConnectionString" --file "$backupDir/$schemaFile"

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Schema dump completed: $schemaFile" -ForegroundColor Green
} else {
    Write-Host "❌ Schema dump failed" -ForegroundColor Red
    Write-Host "Trying with password flag instead..." -ForegroundColor Yellow
    
    # Try with password flag
    .\supabase.exe db dump --db-url "postgresql://$dbUser@$dbHost`:5432/$dbName" --password $dbPassword --file "$backupDir/$schemaFile"
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Schema dump completed with password flag" -ForegroundColor Green
    } else {
        Write-Host "❌ Schema dump failed with both methods" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "🎯 Backup completed!" -ForegroundColor Green

# List created files
if (Test-Path $backupDir) {
    Get-ChildItem $backupDir -Filter "*$timestamp*" | ForEach-Object {
        $sizeKB = [math]::Round($_.Length/1KB, 2)
        Write-Host "  $($_.Name) ($sizeKB KB)" -ForegroundColor White
    }
} else {
    Write-Host "No backup files created" -ForegroundColor Yellow
}
