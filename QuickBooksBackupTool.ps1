# ================================================
# QuickBooks Backup Tool - Clean Progress Bar
# ================================================

$qbExtensions = @('.qbw','.qbb','.qba','.tlg','.nd','.dsn','.qbo')

Write-Host "=== QuickBooks Backup Tool ===" -ForegroundColor Cyan

$allDrives = Get-PSDrive -PSProvider FileSystem | 
    Where-Object { $_.Root -match '^[A-Z]:\\$' -and ($_.Used -ne $null -or $_.Description -match 'Removable') }

Write-Host "Detected drives: $($allDrives.Name -join ', ')" -ForegroundColor Yellow

$foundFiles = @()
$companyFolders = @{}

$fullScan = Read-Host "`nPerform FULL scan on ALL drives? (y/N)"

if ($fullScan -eq 'y' -or $fullScan -eq 'Y') {
    Write-Host "`nStarting full scan... (Ctrl+C to stop)" -ForegroundColor Yellow
    
    foreach ($drive in $allDrives) {
        $driveRoot = $drive.Root
        Write-Host "`n=== Scanning drive: $driveRoot ===" -ForegroundColor Yellow
        
        $scanned = 0
        
        try {
            Get-ChildItem -Path $driveRoot -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
                $scanned++
                
                # Clean single-line progress using Write-Progress
                if ($scanned % 80 -eq 0) {
                    $activity = "Scanning $driveRoot"
                    $status = "Current folder: $($_.DirectoryName)"
                    Write-Progress -Activity $activity -Status $status -PercentComplete -1
                }
                
                if ($_.Extension.ToLower() -in $qbExtensions) {
                    $foundFiles += $_.FullName
                    $companyFolders[$_.DirectoryName] = $true
                    Write-Host "  ✅ Found: $($_.FullName)" -ForegroundColor Green
                }
            }
        } catch {
            Write-Host "  Error on part of drive $driveRoot" -ForegroundColor Red
        }
        
        Write-Progress -Activity "Scanning $driveRoot" -Completed
        Write-Host "  Finished scanning $driveRoot" -ForegroundColor DarkCyan
    }
}

$companyFolders = $companyFolders.Keys | Sort-Object

if ($companyFolders.Count -eq 0) {
    Write-Host "`nNo QuickBooks files found." -ForegroundColor Red
    pause
    exit 1
}

# === Log + Summary + Backup (unchanged) ===
$desktop = [Environment]::GetFolderPath("Desktop")
$logPath = Join-Path $desktop "QuickBooks_Files_Log.txt"
"QuickBooks Files Log - $(Get-Date)" | Out-File $logPath -Encoding UTF8
"="*60 | Out-File $logPath -Append
"Total Files: $($foundFiles.Count)" | Out-File $logPath -Append
"Total Folders: $($companyFolders.Count)" | Out-File $logPath -Append
"`nFound Files:" | Out-File $logPath -Append
$foundFiles | Out-File $logPath -Append

Write-Host "`nLog saved: $logPath" -ForegroundColor Green
Write-Host "`nFound $($foundFiles.Count) file(s) in $($companyFolders.Count) folder(s)" -ForegroundColor Cyan
$companyFolders | ForEach-Object { Write-Host "Folder: $_" }

# Backup section
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backupName = "QuickBooks_Backup_$timestamp"
$tempDir = Join-Path $desktop $backupName
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

Write-Host "`nCopying company folders..." -ForegroundColor Yellow
foreach ($folder in $companyFolders) {
    $dest = Join-Path $tempDir (Split-Path $folder -Leaf)
    try {
        Copy-Item -Path $folder -Destination $dest -Recurse -Force -ErrorAction Stop
        Write-Host "✅ Copied: $folder" -ForegroundColor Green
    } catch {
        Write-Host "⚠️ Skipped some files in: $folder" -ForegroundColor Yellow
    }
}

# Save + ZIP
Add-Type -AssemblyName System.Windows.Forms
$saveDialog = New-Object System.Windows.Forms.SaveFileDialog
$saveDialog.Title = "Save QuickBooks Backup ZIP"
$saveDialog.Filter = "ZIP files (*.zip)|*.zip"
$saveDialog.FileName = "$backupName.zip"
$saveDialog.InitialDirectory = $desktop

if ($saveDialog.ShowDialog() -ne "OK") {
    Write-Host "`nBackup cancelled." -ForegroundColor Red
    Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    pause
    exit 0
}

$zipPath = $saveDialog.FileName
Write-Host "`nCreating ZIP archive..." -ForegroundColor Yellow
Compress-Archive -Path "$tempDir\*" -DestinationPath $zipPath -CompressionLevel Optimal -Force

$sizeMB = [math]::Round((Get-Item $zipPath).Length / 1MB, 1)

Write-Host "`n✅ BACKUP COMPLETE!" -ForegroundColor Green
Write-Host "Saved to: $zipPath"
Write-Host "Size: $sizeMB MB"
Write-Host "Log file: $logPath"

Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
pause
