<#
╔════════════════════════════════════════════════════════════════════════════════════════╗
║  SharePoint Version Cleaner v1.0 - by Dcnigma	                                         ║
║  Features: JSON credentials/config, live colored logs, smooth console updates,         ║
║  robust version deletion logic using CSOM, and live progress table.                    ║
╚════════════════════════════════════════════════════════════════════════════════════════╝
#>

Clear-Host

# --- Global counters ---
$global:fileCounter = 0
$global:folderCounter = 0
$global:versionCounter = 0
$global:lastFileCleaned = ""
$global:liveLog = @()
$global:progressTable = @()
$logFile = "$PWD\Clean_SharePoint_Log_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"

# --- Banner ---
function Show-Banner {
    $bannerLines = @(
        @{ Color='DarkCyan'; Text='╔══════════════════════════════════════════════════════════════════════════════════════════╗' },
        @{ Color='Cyan';     Text='║     ███████╗██╗  ██╗ █████╗ ██████╗ ███████╗    ██████╗  ██████╗ ██╗███╗   ██╗████████╗  ║' },
        @{ Color='Cyan';     Text='║     ██╔════╝██║  ██║██╔══██╗██╔══██╗██╔════╝    ██╔══██╗██╔═══██╗██║████╗  ██║╚══██╔══╝  ║' },
        @{ Color='Cyan';     Text='║     ███████╗███████║███████║██████╔╝█████╗      ██████╔╝██║   ██║██║██╔██╗ ██║   ██║     ║' },
        @{ Color='Cyan';     Text='║     ╚════██║██╔══██║██╔══██║██╔══██╗██╔══╝      ██╔═══╝ ██║   ██║██║██║╚██╗██║   ██║     ║' },
        @{ Color='DarkCyan'; Text='║     ███████║██║  ██║██║  ██║██║  ██║███████╗    ██║     ╚██████╔╝██║██║ ╚████║   ██║     ║' },
        @{ Color='DarkCyan'; Text='║     ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝    ╚═╝      ╚═════╝ ╚═╝╚═╝  ╚═══╝   ╚═╝     ║' },
        @{ Color='Gray';     Text='║                    SharePoint Version Cleaner by Dcnigma.     v1.00                      ║' },
        @{ Color='DarkCyan'; Text='╚══════════════════════════════════════════════════════════════════════════════════════════╝' }
    )

    foreach ($line in $bannerLines) {
        Write-Host $line.Text -ForegroundColor $line.Color
    }
}

# --- Smooth live display + progress table ---
function Update-LiveDisplay {

    $consoleWidth = [Console]::WindowWidth

    if ($consoleWidth -lt 80) { $consoleWidth = 80 }

    # --- Counter line ---
    $consoleWidth = [Console]::WindowWidth
    if ($consoleWidth -lt 80) { $consoleWidth = 80 }

    # Use a short placeholder if no file is processed yet
    $lastFile = if ([string]::IsNullOrEmpty($global:lastFileCleaned)) { "None" } else { $global:lastFileCleaned }

    # Limit the filename/path to fit within console
    $maxFileWidth = [Math]::Max(80, $consoleWidth - 900)  # leave space for counters and icons
    if ($lastFile.Length -gt $maxFileWidth) {
        $lastFile = "..." + $lastFile.Substring($lastFile.Length - ($maxFileWidth - 3))
    }

    # Build counter line
    $counterLine = "📄 Files: {0,-6} | 🧽 Last File Cleaned: {1,-$maxFileWidth} | 🗑️ Total Versions Deleted: {2,-6}" -f `
        $global:fileCounter, $lastFile, $global:versionCounter

    # Write counter line without forcing extra padding
    [Console]::SetCursorPosition(0, 16)
    Write-Host $counterLine

    $logStartRow = 18  #postion clean
    $maxVisibleLines = 8
    $logLines = $global:liveLog | Select-Object -Last $maxVisibleLines

    for ($i = 0; $i -lt $maxVisibleLines; $i++) {
        [Console]::SetCursorPosition(0, $logStartRow + $i)
        if ($i -lt $logLines.Count) {
            $line = [string]$logLines[$i]
            $line = $line.Trim()
            if ($line.Length -gt ($consoleWidth - 1)) {
                $line = $line.Substring(0, $consoleWidth - 4) + "..."
            }
            $paddedLine = $line.PadRight($consoleWidth - 1)
            switch -Regex ($line) {
                "🗑️ Deleted"     { Write-Host $paddedLine -ForegroundColor Green }
                "\| CLEANED \|"   { Write-Host $paddedLine -ForegroundColor Green }
                "\| SKIPPED \|"   { Write-Host $paddedLine -ForegroundColor DarkGray }
                "ℹ️"              { Write-Host $paddedLine -ForegroundColor DarkGray }
                "❌"              { Write-Host $paddedLine -ForegroundColor Red }
                "⚠️"              { Write-Host $paddedLine -ForegroundColor Yellow }
                default           { Write-Host $paddedLine }
            }
        } else {
            Write-Host (" " * $consoleWidth)
        }
    }

    # --- Progress table (top 10 by versions deleted) ---
    [Console]::SetCursorPosition(0, $logStartRow + $maxVisibleLines + 1)
    Write-Host ("📊 Top 10 Files by Versions Deleted").PadRight($consoleWidth) -ForegroundColor Cyan

    $table = $global:progressTable | Sort-Object VersionsDeleted -Descending | Select-Object -First 10

    $maxNameWidth = [Math]::Min(80, ($consoleWidth - 19))  # leave space for VersionsDeleted column
    $header = "{0,15} {1,-$maxNameWidth}" -f "Versions Deleted", "File Name"
    Write-Host $header
    Write-Host ("-" * $consoleWidth)

    foreach ($file in $table) {
        $name = $file.FileName
        if ($name.Length -gt $maxNameWidth) { $name = $name.Substring(0, $maxNameWidth - 3) + "..." }
        $line = "{0,15} {1,-$maxNameWidth}" -f $file.VersionsDeleted, $name
        Write-Host $line
    }
}

# --- Load or create credentials/config ---
$credsPath = ".\creds.json"
$configPath = ".\Clean_SharePoint_Config.json"

if (Test-Path $credsPath) {
    $creds = Get-Content $credsPath | ConvertFrom-Json
    $clientId = $creds.clientId
    $clientSecret = $creds.clientSecret
} else {
    $clientId = Read-Host "Enter your Azure AD App Registration Client ID"
    $clientSecret = Read-Host "Enter your Azure AD App Registration Client Secret"
    $creds = @{ clientId = $clientId; clientSecret = $clientSecret; tenantId = "" }
    $creds | ConvertTo-Json | Set-Content $credsPath
    Write-Host "💾 Credentials saved to $credsPath" -ForegroundColor Green
}

if (Test-Path $configPath) {
    $config = Get-Content $configPath | ConvertFrom-Json
    $siteUrl = $config.siteUrl
    $folderRelativeUrl = $config.folderRelativeUrl
} else {
    $siteUrl = Read-Host "Enter SharePoint site URL (e.g., https://domain.sharepoint.com/sites/sitename)"
    $folderRelativeUrl = Read-Host "Enter folder path in SharePoint (e.g., Gedeelde documenten)"
    $config = @{
        siteUrl = $siteUrl
        folderRelativeUrl = $folderRelativeUrl
    }
    $config | ConvertTo-Json | Set-Content $configPath
    Write-Host "💾 Config saved to $configPath" -ForegroundColor Green
}

# --- Connect to SharePoint ---
Show-Banner
Write-Host "`n🏢 Connecting to SharePoint Online..." -ForegroundColor Yellow
try {
    Connect-PnPOnline -Url $siteUrl -Interactive -ClientId $clientId -ErrorAction Stop
    Write-Host "✅ Connected successfully to $siteUrl" -ForegroundColor Green
} catch {
    Write-Host "❌ Connection failed: $_" -ForegroundColor Red
    exit
}

# --- Recursive cleanup using CSOM version deletion ---
function Clean-FolderRecursively {
    param([string]$FolderUrl)

    try {
        $global:folderCounter++
        $global:liveLog += "$(Get-Date -Format 'HH:mm:ss') 📁 Enumerating folder # $FolderUrl"
        Update-LiveDisplay

        $files = Get-PnPFolderItem -FolderSiteRelativeUrl $FolderUrl -ItemType File -ErrorAction SilentlyContinue
        $ctx = Get-PnPContext

        foreach ($file in $files) {
            $global:fileCounter++
            $global:liveLog += "$(Get-Date -Format 'HH:mm:ss') 📄 Processing file # $($file.Name)"
            Update-LiveDisplay

            try {
                $listItem = Get-PnPFile -Url $file.ServerRelativeUrl -AsListItem
                $ctx.Load($listItem.Versions)
                $ctx.ExecuteQuery()

                $versionsToDelete = $listItem.Versions | Where-Object { $_.IsCurrentVersion -eq $false }
                $deletedCount = 0

                foreach ($version in $versionsToDelete) {
                    $version.DeleteObject()
                    $deletedCount++
                    $global:versionCounter++
                }

                if ($deletedCount -gt 0) {
                    $ctx.ExecuteQuery()
                    $global:lastFileCleaned = "$FolderUrl/$($file.Name)"
                    $global:liveLog += "🗑️ Deleted $deletedCount version(s) from '$($file.Name)'"
                    Add-Content -Path $logFile -Value "$(Get-Date -Format 'u') | CLEANED | $FolderUrl/$($file.Name) | $deletedCount version(s)"
                } else {
                    $global:liveLog += "ℹ️ No old versions found for '$($file.Name)'"
                    Add-Content -Path $logFile -Value "$(Get-Date -Format 'u') | SKIPPED | $FolderUrl/$($file.Name) | No old versions"
                }

                # Update progress table
                $global:progressTable += [PSCustomObject]@{
                    FileName        = $file.Name
                    VersionsDeleted = $deletedCount
                }

                Update-LiveDisplay
            } catch {
                $msg = "$(Get-Date -Format 'u') ❌ Error processing file $($file.Name): $_"
                $global:liveLog += $msg
                Add-Content -Path $logFile -Value $msg
                Update-LiveDisplay
            }
        }

        $subfolders = Get-PnPFolderItem -FolderSiteRelativeUrl $FolderUrl -ItemType Folder -ErrorAction SilentlyContinue
        foreach ($sub in $subfolders) {
            Clean-FolderRecursively "$FolderUrl/$($sub.Name)"
        }

    } catch {
        $msg = "$(Get-Date -Format 'u') ⚠️ Failed folder '$FolderUrl': $_"
        $global:liveLog += $msg
        Add-Content -Path $logFile -Value $msg
        Update-LiveDisplay
    }
}

# --- Start cleanup ---
Write-Host "`n🧭 Starting recursive cleanup in '$folderRelativeUrl' ..."
Write-Host "════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════"
Clean-FolderRecursively $folderRelativeUrl


# --- Summary ---
Clear-Host
Show-Banner
Write-Host ""
Write-Host "✅ Recursive cleanup complete!" -ForegroundColor Green
Write-Host "📁 Folders processed: $global:folderCounter"
Write-Host "📄 Files processed: $global:fileCounter"
Write-Host "🗑️ Versions deleted: $global:versionCounter"
Write-Host "Last file cleaned: $global:lastFileCleaned"
Write-Host ""

# --- Neat Top 10 Summary Table ---
$consoleWidth = [Console]::WindowWidth
if ($consoleWidth -lt 80) { $consoleWidth = 80 }

Write-Host ("📊 Top 10 Files by Versions Deleted (Summary)").PadRight($consoleWidth) -ForegroundColor Cyan

$topFiles = $global:progressTable | Sort-Object VersionsDeleted -Descending | Select-Object -First 10
$maxNameWidth = [Math]::Min(60, $consoleWidth - 15)  # filename column

$header = "{0,-$maxNameWidth} {1,15}" -f "FileName", "VersionsDeleted"
Write-Host $header -ForegroundColor Cyan
Write-Host ("-" * $consoleWidth)

foreach ($file in $topFiles) {
    $name = if ($file.FileName.Length -gt $maxNameWidth) { $file.FileName.Substring(0,$maxNameWidth-3) + "..." } else { $file.FileName }
    $line = "{0,-$maxNameWidth} {1,15}" -f $name, $file.VersionsDeleted
    Write-Host $line
}

Write-Host "📘 Log saved to $logFile" -ForegroundColor Cyan
Disconnect-PnPOnline
Write-Host "`n🔌 Disconnected from SharePoint Online." -ForegroundColor Gray
