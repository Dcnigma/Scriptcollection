# ===============================================
#   OneDrive Cleaner v6 - "Cyan Terminal Pro"
#   Layered Banner + Enumerating Progress + Spinner
#   by Dcnigma
# ===============================================
# =============================================
# 🧩 Microsoft Graph SDK Auto-Installer
# =============================================
#$requiredModules = @(
#    "Microsoft.Graph",
#    "Microsoft.Graph.Authentication",
#    "Microsoft.Graph.Files"
#)

#foreach ($module in $requiredModules) {
#    $installed = Get-Module -ListAvailable -Name $module
#    if (-not $installed) {
#        Write-Host "📦 Installing missing module: $module..."
#        try {
#            Install-Module -Name $module -Force -Scope CurrentUser -ErrorAction Stop
#            Write-Host "✅ Installed: $module"
#        } catch {
#            Write-Host "❌ Failed to install $($module): $($_.Exception.Message)" -ForegroundColor Red
#        }
#    } else {
#        Write-Host "✅ $module already installed."
#    }
#}

# Import the modules (ensures fresh load)
#Import-Module Microsoft.Graph -Force

clear
# --- Layered Banner (top-to-bottom colors) ---
$bannerLines = @(
    @{ Color='DarkCyan'; Text='╔═══════════════════════════════════════════════════════════════════════╗' },
    @{ Color='Cyan';     Text='║    ██████╗ ███╗   ██╗███████╗    ██████╗ ██████╗ ██╗██╗   ██╗███████╗ ║' },
    @{ Color='Cyan';     Text='║   ██╔═══██╗████╗  ██║██╔════╝    ██╔══██╗██╔══██╗██║██║   ██║██╔════╝ ║' },
    @{ Color='Cyan';     Text='║   ██║   ██║██╔██╗ ██║█████╗      ██║  ██║██████╔╝██║██║   ██║█████╗   ║' },
    @{ Color='Cyan';     Text='║   ██║   ██║██║╚██╗██║██╔══╝      ██║  ██║██╔══██╗██║╚██╗ ██╔╝██╔══╝   ║' },
    @{ Color='DarkCyan'; Text='║   ╚██████╔╝██║ ╚████║███████╗    ██████╔╝██║  ██║██║ ╚████╔╝ ███████╗ ║' },
    @{ Color='DarkCyan'; Text='║    ╚═════╝ ╚═╝  ╚═══╝╚══════╝    ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═══╝  ╚══════╝ ║' },
    @{ Color='Gray';     Text='║             OneDrive Version Cleaner by Dcnigma v6.                   ║' },
    @{ Color='DarkCyan'; Text='╚═══════════════════════════════════════════════════════════════════════╝' }
)
foreach ($line in $bannerLines) { Write-Host $line.Text -ForegroundColor $line.Color }

Write-Host "`n🌀 Initializing cleanup engine..." -ForegroundColor Cyan
Write-Host "---------------------------------------------------------" -ForegroundColor Yellow

# --- Status System Setup ---
$script:statusStartY = 12             # pinned area start (banner is 9 lines; we leave spacing)
$global:statusLastDeleted = ""
$global:statusFoundFiles = @()
$global:filesQueue = New-Object System.Collections.Generic.List[object]
$global:folderCount = 0
$global:processedCount = 0
$global:previouslyCleaned = 0

# Spinner
$global:spinnerChars = @('|','/','-','\')
$global:spinnerIndex = 0
$global:isEnumerating = $false

# Utility: get window width (safe)
function Get-WindowWidth {
    try { return $host.UI.RawUI.WindowSize.Width } catch { return 120 }
}

# Utility: gracefully truncate long paths
function Truncate-Path {
    param([string]$path, [int]$maxWidth)
    if (-not $maxWidth -or $maxWidth -lt 20) { $maxWidth = 80 }
    if ($path.Length -le $maxWidth) { return $path }
    # keep the last part (filename) and some parent folders
    $sep = [IO.Path]::DirectorySeparatorChar
    $parts = $path -split '[\\/]'   # split on both slashes
    $filename = $parts[-1]
    $remain = $maxWidth - ($filename.Length + 4) # for '...\' and padding
    if ($remain -gt 0 -and $parts.Count -gt 1) {
        $prefix = $parts[-2]
        if ($prefix.Length -gt $remain) {
            # fall back to show end of filename
            return "…\$filename"
        } else {
            return "…\$prefix\$sep$filename"
        }
    } else {
        return "…\$filename"
    }
}

# Show-Status writes the lines to the pinned area; it clears previous block first
function Show-Status {
    param([string[]]$Lines)
    $width = Get-WindowWidth
    $y = [int]$script:statusStartY
    if ($y -lt 0) { $y = 0 }

    # Clear the region (12 lines by default)
    $height = 20
    for ($i = 0; $i -lt $height; $i++) {
        try {
            $host.UI.RawUI.CursorPosition = @{X=0; Y=($y + $i)}
            Write-Host (" " * $width) -NoNewline
        } catch {
            # ignore if RawUI isn't available
        }
    }

    # Draw lines
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $line = $Lines[$i]
        if ($null -eq $line) { $line = "" }
        if ($line.Length -gt $width) { $line = $line.Substring(0, $width) }
        try { $host.UI.RawUI.CursorPosition = @{X=0; Y=($y + $i)} } catch {}
        $pad = ""
        if ($line.Length -lt $width) { $pad = " " * ($width - $line.Length) }
        Write-Host ($line + $pad)
    }
}

# Update-Status composes the block and shows it
function Update-Status {
    # increment spinner
    $global:spinnerIndex = ($global:spinnerIndex + 1) % $global:spinnerChars.Count
    $spinner = $global:spinnerChars[$global:spinnerIndex]

    $width = Get-WindowWidth
    $queueCount = 0
    if ($global:filesQueue) { $queueCount = $global:filesQueue.Count }

    # Enumerating line (shows spinner while enumerating)
    if ($global:isEnumerating) {
        $enumLine = "🔎 Enumerating: $($global:folderCount) folders scanned, $queueCount files queued... $spinner"
    } else {
        $enumLine = "🔎 Enumerating: idle"
    }

    $lines = @()
    $lines += "🚀 Initializing OneDrive Cleaner..."
    $lines += "💡 Preparing environment..."
    $lines += "🧭 Using Drive ID: $driveId"
    $lines += "🔁 Loaded $($processedFiles.Count) previously cleaned files from log."
    if ($global:lastFolderPath) { $lines += "⏩ Resuming from folder: $($global:lastFolderPath), last file: $($global:lastFileName)" } else { $lines += "" }
    $lines += "📂 Found folder: $($targetFolder.Name)"
    $lines += ("-" * ([math]::Min(87,$width)))
    $lines += $enumLine
    $lines += "💡 Checked $($global:folderCount) folders, processing batch of $queueCount file(s)..."
    $lines += "📊 Progress: $($global:processedCount) files cleaned this run | Previously cleaned: $($global:previouslyCleaned)"

    # show batch preview (truncate long paths)
    $previewMax = [math]::Min($BatchSize, $queueCount)
    for ($i=0; $i -lt $previewMax; $i++) {
        $p = $global:filesQueue[$i].Path
        $pTrunc = Truncate-Path -path $p -maxWidth ($width - 4)
        $lines += "📄 Cleaning: $pTrunc"
    }

    # show recently found files (few)
    $foundShow = [math]::Min(4, $global:statusFoundFiles.Count)
    for ($i = 0; $i -lt $foundShow; $i++) {
        $lines += "🔹 Found file: $($global:statusFoundFiles[$i])"
    }

    if ($global:statusLastDeleted -ne "") {
        $lines += "✅ $($global:statusLastDeleted)"
    }

    while ($lines.Count -lt 20) { $lines += "" }

    Show-Status $lines
}

# --- CONFIGURATION ---
$driveId = "b!xoFeuLyVDUaqQbz1Ooo4HC7kBwXj5PBGkQ98P7fxKqPjYGfcMhAQTYJZOhgAEoCE"
####### 📁📁Start Folder 📁📁######
$targetFolderName = "Gripp/Offertes en Opdrachten/V"
#📁📁
$logFile = "./OneDrive_Cleanup_Log.txt"
$resumeFile = "./OneDrive_Resume.json"
$BatchSize = 5
$BatchFolderThreshold = 10
$SaveAfterEveryFile = $true

# --- Connect to MS Graph if needed ---
if (-not (Get-MgContext)) { Connect-MgGraph -Scopes "Files.ReadWrite.All","User.Read" }

Write-Host "🧭 Using Drive ID: $driveId" -ForegroundColor Cyan

# --- Load processed log & resume ---
$processedFiles = @()
if (Test-Path $logFile) {
    $processedFiles = Get-Content $logFile | ForEach-Object {
        if ($_ -match 'CLEANED \| (.+) \|') { $matches[1] }
    }
    $global:previouslyCleaned = $processedFiles.Count
    Write-Host "🔁 Loaded $($processedFiles.Count) previously cleaned files from log." -ForegroundColor Gray
}

$global:lastFolderPath = $null
$global:lastFileName = $null
$global:resumeReached = $true

if (Test-Path $resumeFile) {
    try {
        $resumeState = Get-Content $resumeFile | ConvertFrom-Json
        if ($resumeState.LastFolder) {
            $global:lastFolderPath = $resumeState.LastFolder
            $global:lastFileName = $resumeState.LastFile
            Write-Host "⏩ Resuming from folder: $($global:lastFolderPath)" -ForegroundColor Cyan
        }
    } catch { Write-Host "⚠️ Failed to read resume file, starting fresh." -ForegroundColor Yellow }
}

# --- Helper: Get-AllDriveItemChildren (paging) ---
function Get-AllDriveItemChildren {
    param([string]$DriveId, [string]$DriveItemId)
    $allItems = @()
    $page = Get-MgDriveItemChild -DriveId $DriveId -DriveItemId $DriveItemId -ErrorAction SilentlyContinue
    if ($null -eq $page) { return $allItems }
    $allItems += $page
    while ($page.NextPageRequest) {
        $page = $page.NextPageRequest.GetAsync().Result
        if ($null -eq $page) { break }
        $allItems += $page
    }
    return $allItems
}

# --- Find-FolderByPath ---
function Find-FolderByPath {
    param([string]$DriveId, [string]$FullPath)
    $parts = $FullPath -split '/'
    $currentId = (Get-MgDriveRoot -DriveId $DriveId).Id
    foreach ($part in $parts) {
        $items = Get-AllDriveItemChildren -DriveId $DriveId -DriveItemId $currentId
        $match = $items | Where-Object { $_.Name -eq $part -and $_.Folder }
        if (-not $match) { return $null }
        $currentId = $match.Id
    }
    return @{ Id = $currentId; Path = $FullPath; Name = $parts[-1] }
}

# --- Save-Resume helper ---
function Save-Resume { param([string]$FolderPath, [string]$FileName)
    @{ LastFolder = $FolderPath; LastFile = $FileName } | ConvertTo-Json | Set-Content $resumeFile
}

# --- Enumerate & Queue ---
function Enumerate-Files {
    param([string]$DriveId, [string]$FolderId, [string]$Path)
    # mark enumerating active
    $global:isEnumerating = $true

    $items = Get-AllDriveItemChildren -DriveId $DriveId -DriveItemId $FolderId

    # files first (breadth-first)
    foreach ($item in $items) {
        $itemPath = "$Path/$($item.Name)"
        if ($item.File -and -not ($processedFiles -contains $itemPath)) {
            # resume logic
            if (-not $global:resumeReached -and $global:lastFolderPath) {
                if ($Path -ne $global:lastFolderPath) { continue }
                elseif ($item.Name -eq $global:lastFileName) {
                    $global:resumeReached = $true
                    Write-Host "✅ Reached resume file: $itemPath -> resuming after this file" -ForegroundColor Cyan
                    continue
                } else { continue }
            }

            $global:filesQueue.Add([PSCustomObject]@{ Id = $item.Id; Name = $item.Name; Path = $itemPath })
            #$global:statusFoundFiles.Insert(0, "$($item.Name) | Queue: $($global:filesQueue.Count)")
            if ($global:statusFoundFiles.Count -gt 20) { $global:statusFoundFiles = $global:statusFoundFiles[0..19] }

            # update status as we discover
            Update-Status

            if ($global:filesQueue.Count -ge $BatchSize) {
                Update-Status
                Process-Batch
            }
        }
    }

    # recurse folders
    foreach ($item in $items) {
        if ($item.Folder) {
            $global:folderCount++
            # update enumerating status when folder count increases
            Update-Status
            if ($global:folderCount -ge $BatchFolderThreshold -and $global:filesQueue.Count -gt 0) {
                Update-Status
                Process-Batch
                $global:folderCount = 0
            }
            Enumerate-Files -DriveId $DriveId -FolderId $item.Id -Path "$Path/$($item.Name)"
        }
    }

    # when done with this branch, if we are top-level finishing, keep enumerating true until top caller clears
    # leave $global:isEnumerating to caller to set false after full tree processed
}

# --- Process Batch ---
function Process-Batch {
    $localBatch = $global:filesQueue.ToArray()
    # don't clear global queue until processed (so preview shows)
    Update-Status
    Write-Host "`n🚀 Starting batch of $($localBatch.Count) file(s)" -ForegroundColor Cyan
    foreach ($file in $localBatch) {
        try {
            # show current file in status immediately
            Update-Status

            $versions = Get-MgDriveItemVersion -DriveId $driveId -DriveItemId $file.Id -ErrorAction SilentlyContinue
            if (-not $versions -or $versions.Count -eq 0) {
                Add-Content -Path $logFile -Value "$(Get-Date) | CLEANED | $($file.Path) | 0 version(s)"
                $global:statusLastDeleted = "Deleted in file: $($file.Name) | 0 version(s)"
            } else {
                $deletable = $versions | Where-Object { -not $_.IsCurrentVersion -and $_.Id -ne "current" }
                $deleted = 0
                foreach ($v in $deletable) {
                    try {
                        Remove-MgDriveItemVersion -DriveId $driveId -DriveItemId $file.Id -DriveItemVersionId $v.Id -ErrorAction Stop
                        $deleted++
                        Start-Sleep -Milliseconds 80
                    } catch {
                        $msg = $_.Exception.Message
                        if ($msg -and $msg -like "*You cannot delete the current version*") {
                            # silently ignore
                        } else {
                            Write-Host "⚠️ Could not delete version id $($v.Id) for $($file.Path): $msg" -ForegroundColor Yellow
                        }
                    }
                }
                Add-Content -Path $logFile -Value "$(Get-Date) | CLEANED | $($file.Path) | $deleted version(s)"
                $global:statusLastDeleted = "Deleted in file: $($file.Name) | $deleted version(s)"
            }

            $global:processedCount++
            # remove processed file from global filesQueue (safe remove by matching Id)
            for ($i = $global:filesQueue.Count - 1; $i -ge 0; $i--) {
                if ($global:filesQueue[$i].Id -eq $file.Id) { $global:filesQueue.RemoveAt($i); break }
            }

            Update-Status

            if ($SaveAfterEveryFile) { Save-Resume -FolderPath (Split-Path $file.Path) -FileName $file.Name }

        } catch {
            Add-Content -Path $logFile -Value "$(Get-Date) | ERROR | $($file.Path) | $_"
            $global:statusLastDeleted = "ERROR cleaning $($file.Name)"
            Update-Status
        }
    }
    Update-Status
}

# --- START RUN ---
Add-Content -Path $logFile -Value "=== START RUN $(Get-Date) ==="
$global:startTime = Get-Date

$targetFolder = Find-FolderByPath -DriveId $driveId -FullPath $targetFolderName
if (-not $targetFolder) { Write-Host "❌ Folder '$targetFolderName' not found." -ForegroundColor Red; exit }
Write-Host "📂 Found folder: $($targetFolder.Name)" -ForegroundColor Green

# mark full enumeration active, then call enumerator; set false after
$global:isEnumerating = $true
Update-Status
Enumerate-Files -DriveId $driveId -FolderId $targetFolder.Id -Path $targetFolder.Path
$global:isEnumerating = $false

# process any remaining queue
if ($global:filesQueue.Count -gt 0) {
    Update-Status
    Process-Batch
}

Add-Content -Path $logFile -Value "=== END RUN $(Get-Date) ===`n"

# --- Final Summary ---
$endTime = Get-Date
$duration = New-TimeSpan -Start $global:startTime -End $endTime
Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Yellow
Write-Host "✅ Cleaning completed successfully!" -ForegroundColor Green
Write-Host "📂 Total this run: $($global:processedCount) files cleaned | Previously cleaned: $($global:previouslyCleaned)" -ForegroundColor Cyan
Write-Host "🕓 Duration: $($duration.ToString())" -ForegroundColor Cyan
Write-Host "📁 Target folder: $($targetFolder.Path)" -ForegroundColor DarkCyan
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Yellow
