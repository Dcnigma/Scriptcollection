<#
╔════════════════════════════════════════════════════════════════════════════════════════╗
║  SharePoint Path Length Scanner v1.3 - by Dcnigma                                      ║
║  NEW: Segment-based rename — rename ANY folder in the path chain, not just the leaf.   ║
║  Auto-updates affected child paths after parent renames.                               ║
║  Compatible with PowerShell on macOS (pwsh).                                           ║
#>

Clear-Host

# --- Global counters & state ---
$global:fileCounter    = 0
$global:folderCounter  = 0
$global:warningCount   = 0
$global:criticalCount  = 0
$global:okCount        = 0
$global:results        = @()
$global:rollingWindow  = @()
$global:currentFolder  = ""
$global:anchorRow      = 0
$global:useDashboard   = $true
$global:renameResults  = @()
$timestamp             = Get-Date -Format 'yyyyMMdd_HHmmss'
$logFile               = "PathScanner_Log_$timestamp.txt"
$csvFile               = "PathLength_Report_$timestamp.csv"
$renameCsv             = "PathRename_Report_$timestamp.csv"

$global:maxWindowItems = 10
$global:spinnerFrames  = @('⠋','⠙','⠹','⠸','⠼','⠴','⠦','⠧','⠇','⠏')
$global:spinnerIndex   = 0

# Abbreviation dictionary
$global:abbreviations = @{
    'Documenten'='Docs'; 'Document'='Doc'; 'Documents'='Docs'
    'Presentaties'='Pres'; 'Presentatie'='Pres'; 'Presentation'='Pres'
    'Projecten'='Proj'; 'Project'='Proj'
    'Rapport'='Rpt'; 'Rapporten'='Rpts'; 'Report'='Rpt'; 'Reports'='Rpts'
    'Vergadering'='Mtg'; 'Vergaderingen'='Mtgs'; 'Meeting'='Mtg'; 'Meetings'='Mtgs'; 'MeetingNotes'='MtgNotes'
    'Contract'='Contr'; 'Contracten'='Contrs'; 'Contracts'='Contrs'
    'Klanten'='Klts'; 'Klant'='Klt'; 'Customer'='Cust'; 'Customers'='Custs'; 'CustomerSuccess'='CustSucc'
    'Versie'='v'; 'Version'='v'; 'Definitief'='Def'; 'Final'='Fin'; 'Concept'='Cpt'
    'Backup'='Bkp'; 'Archief'='Arch'; 'Archive'='Arch'
    'Administratie'='Adm'; 'Administration'='Adm'
    'Afdeling'='Afd'; 'Department'='Dept'
    'Information'='Info'; 'Informatie'='Info'
    'Management'='Mgmt'; 'Maatschappij'='Mij'
    'Bedrijf'='Bdr'; 'Company'='Co'
    'Organisatie'='Org'; 'Organization'='Org'
    'Onboarding'='Onb'; 'OnboardingMaterials'='OnbMat'
    'Materials'='Mat'; 'Library'='Lib'
    'Compliance'='Comp'; 'ComplianceAndRegulatoryAffairs'='CompReg'
    'Regulatory'='Reg'; 'Affairs'='Aff'
    'HumanResources'='HR'; 'Human'='Hu'; 'Resources'='Res'
    'Procurement'='Proc'; 'Finance'='Fin'; 'Marketing'='Mkt'
    'Vendor'='Vnd'; 'VendorOnboardingAndManagement'='VndOnbMgmt'
    'Employee'='Emp'; 'EmployeeOnboardingMaterials'='EmpOnbMat'
    'Northstar'='NS'; 'Aurora'='Aur'; 'Thunder'='Thd'
    'Quarter'='Q'
    'Northern'='N'; 'Southern'='S'; 'Eastern'='E'; 'Western'='W'
}

# --- Helpers ---
function Get-SafeConsoleWidth {
    try { $w = :WindowWidth; if ($w -lt 80) { $w = 80 }; return $w } catch { return 120 }
}

function Pad-Line {
    param([string]$Text)
    $width = Get-SafeConsoleWidth
    if ($Text.Length -ge $width) { return $Text.Substring(0, $width - 1) }
    return $Text.PadRight($width - 1)
}

function Show-Banner {
    $bannerLines = @(
        @{ Color='DarkCyan'; Text='╔══════════════════════════════════════════════════════════════════════════════════════════╗' },
        @{ Color='Cyan';     Text='║     ██████╗  █████╗ ████████╗██╗  ██╗    ███████╗ ██████╗ █████╗ ███╗   ██╗            ║' },
        @{ Color='Cyan';     Text='║     ██╔══██╗██╔══██╗╚══██╔══╝██║  ██║    ██╔════╝██╔════╝██╔══██╗████╗  ██║            ║' },
        @{ Color='Cyan';     Text='║     ██████╔╝███████║   ██║   ███████║    ███████╗██║     ███████║██╔██╗ ██║            ║' },
        @{ Color='Cyan';     Text='║     ██╔═══╝ ██╔══██║   ██║   ██╔══██║    ╚════██║██║     ██╔══██║██║╚██╗██║            ║' },
        @{ Color='DarkCyan'; Text='║     ██║     ██║  ██║   ██║   ██║  ██║    ███████║╚██████╗██║  ██║██║ ╚████║            ║' },
        @{ Color='DarkCyan'; Text='║     ╚═╝     ╚═╝  ╚═╝   ╚═╝   ╚═╝  ╚═╝    ╚══════╝ ╚═════╝╚═╝  ╚═╝╚═╝  ╚═══╝            ║' },
        @{ Color='Gray';     Text='║              SharePoint Path Length Scanner by Dcnigma.     v1.30                      ║' },
        @{ Color='DarkCyan'; Text='╚══════════════════════════════════════════════════════════════════════════════════════════╝' }
    )
    foreach ($line in $bannerLines) { Write-Host $line.Text -ForegroundColor $line.Color }
}

function Get-PathStatus {
    param([int]$Length)
    if ($Length -ge $global:criticalThreshold) { return "Critical" }
    if ($Length -ge $global:warningThreshold)  { return "Warning" }
    return "OK"
}

function Get-StatusColor {
    param([string]$Status)
    switch ($Status) { "Critical"{"Red"}; "Warning"{"Yellow"}; default{"Green"} }
}

function Get-StatusIcon {
    param([string]$Status)
    switch ($Status) { "Critical"{"🔴"}; "Warning"{"🟡"}; default{"🟢"} }
}

function Set-CursorSafe {
    param([int]$Row, [int]$Col = 0)
    try { :SetCursorPosition($Col, $Row) } catch { $global:useDashboard = $false }
}

function Update-Dashboard {
    if (-not $global:useDashboard) { return }
    $width = Get-SafeConsoleWidth
    Set-CursorSafe -Row $global:anchorRow

    $spin = $global:spinnerFrames[$global:spinnerIndex % $global:spinnerFrames.Count]
    $global:spinnerIndex++

    $folderDisplay = $global:currentFolder
    $maxFolderLen  = $width - 20
    if ($folderDisplay.Length -gt $maxFolderLen) {
        $folderDisplay = "..." + $folderDisplay.Substring($folderDisplay.Length - $maxFolderLen + 3)
    }
    Write-Host (Pad-Line "$spin Scanning: $folderDisplay") -ForegroundColor DarkCyan
    Write-Host (Pad-Line ("─" * ($width - 1))) -ForegroundColor DarkGray

    $counterLine = "📁 Folders: $($global:folderCounter)  |  📄 Files: $($global:fileCounter)  |  🟢 OK: $($global:okCount)  |  🟡 Warn: $($global:warningCount)  |  🔴 Crit: $($global:criticalCount)"
    Write-Host (Pad-Line $counterLine) -ForegroundColor White
    Write-Host (Pad-Line ("─" * ($width - 1))) -ForegroundColor DarkGray

    for ($i = 0; $i -lt $global:maxWindowItems; $i++) {
        if ($i -lt $global:rollingWindow.Count) {
            $entry = $global:rollingWindow[$i]
            $text  = $entry.Text
            $maxLen = $width - 5
            if ($text.Length -gt $maxLen) { $text = $text.Substring(0, $maxLen - 3) + "..." }
            Write-Host (Pad-Line "$($entry.Icon) $text") -ForegroundColor $entry.Color
        } else {
            Write-Host (Pad-Line " ") -ForegroundColor DarkGray
        }
    }
    Write-Host (Pad-Line ("─" * ($width - 1))) -ForegroundColor DarkGray
}

function Add-RollingItem {
    param([string]$Icon, [string]$Color, [string]$Text)
    $item = @{ Icon=$Icon; Color=$Color; Text=$Text }
    $global:rollingWindow = @($item) + $global:rollingWindow
    if ($global:rollingWindow.Count -gt $global:maxWindowItems) {
        $global:rollingWindow = $global:rollingWindow[0..($global:maxWindowItems - 1)]
    }
    Update-Dashboard
}

# =====================================================================================
# SMART SUGGESTION
# =====================================================================================
function Get-SmartSuggestion {
    param(
        [string]$OriginalName,
        [string]$ItemType,
        [int]$ParentPathLength,
        [int]$TargetMaxTotal
    )
    $maxNameLen = $TargetMaxTotal - $ParentPathLength - 1
    if ($maxNameLen -lt 5) { $maxNameLen = 5 }

    $extension = ""
    $baseName  = $OriginalName
    if ($ItemType -eq "File") {
        $lastDot = $OriginalName.LastIndexOf('.')
        if ($lastDot -gt 0 -and $lastDot -lt $OriginalName.Length - 1) {
            $extension = $OriginalName.Substring($lastDot)
            $baseName  = $OriginalName.Substring(0, $lastDot)
        }
    }

    $suggestion = $baseName
    # Sort by length descending so longest matches replace first
    foreach ($key in ($global:abbreviations.Keys | Sort-Object Length -Descending)) {
        $pattern    = "\b" + :Escape($key) + "\b"
        $suggestion = :Replace($suggestion, $pattern, $global:abbreviations[$key], 'IgnoreCase')
    }

    $suggestion = $suggestion -replace '\s+', '_'
    $suggestion = $suggestion -replace '[\\/:*?"<>|#%]', ''
    $suggestion = $suggestion -replace '_+', '_'
    $suggestion = $suggestion.Trim('_', '.', ' ')

    if (:IsNullOrWhiteSpace($suggestion)) { $suggestion = "renamed" }

    $availableForBase = $maxNameLen - $extension.Length
    if ($availableForBase -lt 3) { $availableForBase = 3 }
    if ($suggestion.Length -gt $availableForBase) {
        $suggestion = $suggestion.Substring(0, $availableForBase).Trim('_', '.', ' ')
    }

    return $suggestion + $extension
}

function Test-ValidSPName {
    param([string]$Name)
    if (:IsNullOrWhiteSpace($Name))           { return @{ Valid=$false; Reason="Name cannot be empty." } }
    if ($Name -match '[\\/:*?"<>|#%]')                  { return @{ Valid=$false; Reason="Name contains invalid chars: \ / : * ? `" < > | # %" } }
    if ($Name.StartsWith('.') -or $Name.EndsWith('.'))  { return @{ Valid=$false; Reason="Name cannot start or end with a dot." } }
    if ($Name.Length -gt 255)                           { return @{ Valid=$false; Reason="Name exceeds 255 characters." } }
    return @{ Valid=$true; Reason="" }
}

# =====================================================================================
# CREDENTIALS
# =====================================================================================
$credsPath = "./creds.json"
if (Test-Path $credsPath) {
    $creds        = Get-Content $credsPath | ConvertFrom-Json
    $clientId     = $creds.clientId
    $clientSecret = $creds.clientSecret
    Write-Host "🔑 Credentials loaded from $credsPath" -ForegroundColor Green
} else {
    $clientId     = Read-Host "Enter your Azure AD App Registration Client ID"
    $clientSecret = Read-Host "Enter your Azure AD App Registration Client Secret"
    $creds = @{ clientId=$clientId; clientSecret=$clientSecret }
    $creds | ConvertTo-Json | Set-Content $credsPath
    Write-Host "💾 Credentials saved to $credsPath" -ForegroundColor Green
}

# =====================================================================================
# CONFIG
# =====================================================================================
$configPath = "./PathScanner_Config.json"
if (Test-Path $configPath) {
    $config            = Get-Content $configPath | ConvertFrom-Json
    $siteUrl           = $config.siteUrl
    $folderRelativeUrl = $config.folderRelativeUrl
    $localSyncBasePath = if ($config.PSObject.Properties['localSyncBasePath']) { $config.localSyncBasePath } else { "" }
    $global:warningThreshold  = if ($config.PSObject.Properties['warningThreshold'])  { $config.warningThreshold }  else { 200 }
    $global:criticalThreshold = if ($config.PSObject.Properties['criticalThreshold']) { $config.criticalThreshold } else { 260 }
    Write-Host "📋 Config loaded from $configPath" -ForegroundColor Green
} else {
    $siteUrl           = Read-Host "Enter SharePoint site URL"
    $folderRelativeUrl = Read-Host "Enter folder path in SharePoint"
    $localSyncBasePath = Read-Host "Enter local sync base path (or Enter to skip)"
    $warnInput = Read-Host "Enter warning threshold (default 200)"
    $critInput = Read-Host "Enter critical threshold (default 260)"
    $global:warningThreshold  = if ($warnInput) { [int]$warnInput } else { 200 }
    $global:criticalThreshold = if ($critInput) { [int]$critInput } else { 260 }
    $config = @{
        siteUrl=$siteUrl; folderRelativeUrl=$folderRelativeUrl; localSyncBasePath=$localSyncBasePath
        warningThreshold=$global:warningThreshold; criticalThreshold=$global:criticalThreshold
    }
    $config | ConvertTo-Json | Set-Content $configPath
    Write-Host "💾 Config saved to $configPath" -ForegroundColor Green
}

Clear-Host
Show-Banner
Write-Host ""
Write-Host "⚙️  Active Settings:" -ForegroundColor Cyan
Write-Host "   Site URL           : $siteUrl" -ForegroundColor White
Write-Host "   Folder             : $folderRelativeUrl" -ForegroundColor White
Write-Host "   Local Sync Base    : $(if ($localSyncBasePath) { $localSyncBasePath } else { '(not set)' })" -ForegroundColor White
Write-Host "   Warning Threshold  : $($global:warningThreshold) chars" -ForegroundColor Yellow
Write-Host "   Critical Threshold : $($global:criticalThreshold) chars" -ForegroundColor Red
Write-Host ""

# =====================================================================================
# CONNECT
# =====================================================================================
Write-Host "🏢 Connecting to SharePoint Online..." -ForegroundColor Yellow
try {
    Connect-PnPOnline -Url $siteUrl -Interactive -ClientId $clientId -ErrorAction Stop
    Write-Host "✅ Connected" -ForegroundColor Green
} catch {
    Write-Host "❌ Connection failed: $_" -ForegroundColor Red
    Write-Host "💡 Install PnP.PowerShell -Scope CurrentUser" -ForegroundColor Yellow
    exit
}

try {
    $web = Get-PnPWeb
    $global:webServerRelativeUrl = $web.ServerRelativeUrl.TrimEnd('/')
} catch {
    $global:webServerRelativeUrl = ""
}

Write-Host ""
Write-Host "🧭 Starting path length scan..." -ForegroundColor Cyan
Write-Host ""

try {
    $global:anchorRow = :CursorTop
    for ($i = 0; $i -lt ($global:maxWindowItems + 5); $i++) { Write-Host "" }
    $global:useDashboard = $true
} catch {
    $global:useDashboard = $false
}

if ($global:useDashboard) { Update-Dashboard }
try { :CursorVisible = $false } catch {}

# =====================================================================================
# RECURSIVE CRAWL
# =====================================================================================
function Scan-FolderRecursively {
    param([string]$FolderUrl)
    $global:currentFolder = $FolderUrl
    try {
        $items = Get-PnPFolderItem -FolderSiteRelativeUrl $FolderUrl -ErrorAction Stop
    } catch {
        Add-Content -Path $logFile -Value "⚠️ Could not access: $FolderUrl - $_"
        return
    }
    foreach ($item in $items) {
        $isFolder = $item.PSObject.Properties['ItemCount'] -ne $null -or $item.PSObject.TypeNames -match 'Folder'
        $itemName = $item.Name
        $spPath   = "$FolderUrl/$itemName"
        if ($isFolder) { $type="Folder"; $global:folderCounter++ } else { $type="File"; $global:fileCounter++ }
        $spPathLength = $spPath.Length
        if ($localSyncBasePath) {
            $localPath = "$localSyncBasePath/$spPath"; $localPathLength = $localPath.Length
        } else {
            $localPath = ""; $localPathLength = $spPathLength
        }
        $checkLength = if ($localSyncBasePath) { $localPathLength } else { $spPathLength }
        $status     = Get-PathStatus -Length $checkLength
        $statusIcon = Get-StatusIcon -Status $status
        $color      = Get-StatusColor -Status $status
        switch ($status) {
            "OK"{$global:okCount++}; "Warning"{$global:warningCount++}; "Critical"{$global:criticalCount++}
        }
        $global:results += [PSCustomObject]@{
            Type=$type; Name=$itemName; SharePointPath=$spPath; PathLength=$spPathLength
            EstimatedLocalPath=$localPath; LocalPathLength=$localPathLength; Status=$status
        }
        Add-Content -Path $logFile -Value "[$type] $status ($checkLength) $spPath"
        if ($global:useDashboard) {
            Add-RollingItem -Icon $statusIcon -Color $color -Text "[$type] ($checkLength) $spPath"
        }
        if ($isFolder -and $itemName -notmatch '^_|^Forms$') {
            Scan-FolderRecursively -FolderUrl $spPath
        }
    }
}

Scan-FolderRecursively -FolderUrl $folderRelativeUrl
try { :CursorVisible = $true } catch {}
$global:results | Export-Csv -Path $csvFile -NoTypeInformation -Encoding UTF8

# =====================================================================================
# SUMMARY
# =====================================================================================
if ($global:useDashboard) {
    Set-CursorSafe -Row ($global:anchorRow + $global:maxWindowItems + 6)
}
Clear-Host
Show-Banner
Write-Host ""
Write-Host "✅ Scan Complete!" -ForegroundColor Green
$consoleWidth = Get-SafeConsoleWidth
Write-Host ("═" * $consoleWidth) -ForegroundColor DarkGray
Write-Host "📁 Folders : $($global:folderCounter)   📄 Files : $($global:fileCounter)   📊 Total : $($global:folderCounter + $global:fileCounter)" -ForegroundColor White
Write-Host "🟢 OK : $($global:okCount)   🟡 Warn : $($global:warningCount)   🔴 Crit : $($global:criticalCount)" -ForegroundColor White
Write-Host ""
Write-Host "📊 CSV : $csvFile" -ForegroundColor Cyan
Write-Host "📘 Log : $logFile" -ForegroundColor Cyan
Write-Host ""

# =====================================================================================
# SEGMENT-BASED INTERACTIVE RENAME MODULE (v1.3 NEW)
# =====================================================================================
function Get-PathSegments {
    param([string]$Path, [string]$RootPrefix)
    $segments = @()
    $cumulative = 0
    $remainder = $Path
    if ($RootPrefix -and $Path.StartsWith($RootPrefix)) {
        $segments += [PSCustomObject]@{
            Index = 0; Name = $RootPrefix; IsRoot = $true; IsLeaf = $false
            CumulativeLength = $RootPrefix.Length; SegmentLength = $RootPrefix.Length
        }
        $cumulative = $RootPrefix.Length
        $remainder  = $Path.Substring($RootPrefix.Length).TrimStart('/')
    }
    $parts = $remainder -split '/'
    for ($i = 0; $i -lt $parts.Count; $i++) {
        $name = $parts[$i]
        if (:IsNullOrWhiteSpace($name)) { continue }
        $cumulative += 1 + $name.Length
        $isLeaf = ($i -eq $parts.Count - 1)
        $segments += [PSCustomObject]@{
            Index = $segments.Count; Name = $name; IsRoot = $false; IsLeaf = $isLeaf
            CumulativeLength = $cumulative; SegmentLength = $name.Length
        }
    }
    return $segments
}

function Show-PathBreakdown {
    param([array]$Segments, [int]$TotalLength)
    Write-Host ""
    Write-Host "📂 Path Breakdown — pick a segment number to rename:" -ForegroundColor Cyan
    Write-Host ("─" * $consoleWidth) -ForegroundColor DarkGray
    $nonRoot     = $Segments | Where-Object { -not $_.IsRoot }
    $topLongest  = $nonRoot | Sort-Object SegmentLength -Descending | Select-Object -First 3
    $topNames    = $topLongest.Name
    foreach ($seg in $Segments) {
        if ($seg.IsRoot) {
            $label = "[ROOT]"; $marker = "      "; $color = "DarkGray"; $display = "$($seg.Name)/"
        } else {
            $label = "[$($seg.Index)]"
            if ($seg.IsLeaf)                       { $marker = "[LEAF]"; $color = "Yellow" }
            elseif ($topNames -contains $seg.Name) { $marker = "🔴    "; $color = "Red" }
            else                                   { $marker = "      "; $color = "White" }
            $display = $seg.Name
            if ($display.Length -gt 55) { $display = $display.Substring(0, 52) + "..." }
        }
        $line = "{0,-5} {1,-7} {2,-58} len: {3,4} | cum: {4,4}" -f $label, $marker, $display, $seg.SegmentLength, $seg.CumulativeLength
        Write-Host $line -ForegroundColor $color
    }
    Write-Host ("─" * $consoleWidth) -ForegroundColor DarkGray
    Write-Host "Total path length: $TotalLength chars  |  Threshold: $($global:criticalThreshold)" -ForegroundColor Yellow
    Write-Host ""
}

function Apply-PathRename {
    param([string]$OldPathPrefix, [string]$NewPathPrefix)
    $affected = 0
    for ($i = 0; $i -lt $global:results.Count; $i++) {
        $entry = $global:results[$i]
        if ($entry.SharePointPath -eq $OldPathPrefix -or $entry.SharePointPath.StartsWith($OldPathPrefix + "/")) {
            $newPath = $NewPathPrefix + $entry.SharePointPath.Substring($OldPathPrefix.Length)
            $entry.SharePointPath = $newPath
            $entry.PathLength     = $newPath.Length
            if ($localSyncBasePath) {
                $entry.EstimatedLocalPath = "$localSyncBasePath/$newPath"
                $entry.LocalPathLength    = $entry.EstimatedLocalPath.Length
            } else {
                $entry.LocalPathLength = $newPath.Length
            }
            $checkLen = if ($localSyncBasePath) { $entry.LocalPathLength } else { $entry.PathLength }
            $entry.Status = Get-PathStatus -Length $checkLen
            $affected++
        }
    }
    return $affected
}

function Invoke-SegmentRename {
    param(
        [string]$CurrentFullPath,
        [array]$Segments,
        [int]$SegmentIndex,
        [string]$NewSegmentName,
        [string]$ItemType
    )
    $oldParts = @()
    foreach ($seg in $Segments) {
        if ($seg.IsRoot) { $oldParts += $seg.Name; continue }
        $oldParts += $seg.Name
        if ($seg.Index -eq $SegmentIndex) { break }
    }
    if ($Segments[0].IsRoot) {
        $oldPrefix = $oldParts[0] + "/" + ($oldParts[1..($oldParts.Count - 1)] -join "/")
    } else {
        $oldPrefix = $oldParts -join "/"
    }
    $newParts = @($oldParts[0..($oldParts.Count - 2)]) + @($NewSegmentName)
    if ($Segments[0].IsRoot) {
        $newPrefix = $newParts[0] + "/" + ($newParts[1..($newParts.Count - 1)] -join "/")
    } else {
        $newPrefix = $newParts -join "/"
    }
    $chosenSeg = $Segments[$SegmentIndex]
    $segIsFile = $chosenSeg.IsLeaf -and ($ItemType -eq "File")
    $serverRelOld = if ($global:webServerRelativeUrl) { "$($global:webServerRelativeUrl)/$oldPrefix" } else { "/$oldPrefix" }
    try {
        if ($segIsFile) {
            Rename-PnPFile -ServerRelativeUrl $serverRelOld -TargetFileName $NewSegmentName -Force -ErrorAction Stop
        } else {
            Rename-PnPFolder -Folder $serverRelOld -TargetFolderName $NewSegmentName -ErrorAction Stop
        }
        $affected = Apply-PathRename -OldPathPrefix $oldPrefix -NewPathPrefix $newPrefix
        return @{ Success = $true; OldPrefix = $oldPrefix; NewPrefix = $newPrefix; Affected = $affected; Error = "" }
    } catch {
        return @{ Success = $false; OldPrefix = $oldPrefix; NewPrefix = $newPrefix; Affected = 0; Error = $_.ToString() }
    }
}

# =====================================================================================
# RENAME WORKFLOW
# =====================================================================================
if ($global:criticalCount -eq 0) {
    Write-Host "🎉 No critical paths found!" -ForegroundColor Green
    Disconnect-PnPOnline
    exit
}

Write-Host ("═" * $consoleWidth) -ForegroundColor DarkGray
Write-Host "🛠️  SEGMENT-BASED RENAME MODULE (v1.3)" -ForegroundColor Magenta
Write-Host ("─" * $consoleWidth) -ForegroundColor DarkGray
Write-Host "$($global:criticalCount) critical item(s) exceed $($global:criticalThreshold) characters." -ForegroundColor Yellow
Write-Host "You can now rename ANY folder in the path — not just the leaf." -ForegroundColor Gray
Write-Host "Renaming a parent folder automatically fixes ALL children under it!" -ForegroundColor Green
Write-Host ""
$proceed = Read-Host "Start interactive rename now? (Y/N)"
if ($proceed -notmatch '^[Yy]') {
    Write-Host "👍 Rename skipped." -ForegroundColor Cyan
    Disconnect-PnPOnline
    exit
}

$rootPrefix = $folderRelativeUrl
$quitRename       = $false
$processedIndices = @{}
$itemCounter      = 0

while (-not $quitRename) {
    $criticalItems = $global:results | Where-Object { $_.Status -eq "Critical" }
    if ($criticalItems.Count -eq 0) {
        Write-Host ""
        Write-Host "🎉 All critical paths have been resolved!" -ForegroundColor Green
        break
    }

    $sorted = $criticalItems | Sort-Object @{
        Expression = { ($_.SharePointPath.ToCharArray() | Where-Object { $_ -eq '/' }).Count }
        Descending = $true
    }, @{ Expression = { $_.SharePointPath.Length }; Descending = $true }

    $item = $null
    foreach ($cand in $sorted) {
        if (-not $processedIndices.ContainsKey($cand.SharePointPath)) {
            $item = $cand
            break
        }
    }
    if (-not $item) {
        Write-Host ""
        Write-Host "✅ All critical items have been processed." -ForegroundColor Green
        break
    }

    $itemCounter++
    Clear-Host
    Show-Banner
    Write-Host ""
    $remaining = ($global:results | Where-Object { $_.Status -eq "Critical" }).Count
    Write-Host "🛠️  RENAME MODE  -  Item #$itemCounter  |  $remaining critical remaining" -ForegroundColor Magenta
    Write-Host ("═" * $consoleWidth) -ForegroundColor DarkGray

    $renamedCnt = ($global:renameResults | Where-Object { $_.Status -eq 'Renamed' }).Count
    $skippedCnt = ($global:renameResults | Where-Object { $_.Status -eq 'Skipped' }).Count
    $failedCnt  = ($global:renameResults | Where-Object { $_.Status -eq 'Failed' }).Count
    Write-Host "✅ Renamed: $renamedCnt  |  ⏭️  Skipped: $skippedCnt  |  ❌ Failed: $failedCnt" -ForegroundColor Cyan
    Write-Host ""

    Write-Host "🔴 CRITICAL $($item.Type.ToUpper())" -ForegroundColor Red
    Write-Host "   Full path : " -NoNewline -ForegroundColor Gray
    Write-Host $item.SharePointPath -ForegroundColor White
    Write-Host "   SP length : " -NoNewline -ForegroundColor Gray
    Write-Host "$($item.PathLength) chars" -ForegroundColor Red
    if ($item.LocalPathLength -gt 0) {
        Write-Host "   Local len : " -NoNewline -ForegroundColor Gray
        Write-Host "$($item.LocalPathLength) chars" -ForegroundColor Red
    }

    $segments  = Get-PathSegments -Path $item.SharePointPath -RootPrefix $rootPrefix
    $totalLen  = if ($localSyncBasePath) { $item.LocalPathLength } else { $item.PathLength }
    Show-PathBreakdown -Segments $segments -TotalLength $totalLen

    $renamableSegs = $segments | Where-Object { -not $_.IsRoot }
    $maxIdx = ($renamableSegs | Measure-Object -Property Index -Maximum).Maximum

    Write-Host "Options:" -ForegroundColor Cyan
    Write-Host "  1-$maxIdx        → Rename that segment" -ForegroundColor White
    Write-Host "  [Enter]    → Smart auto-fix (rename the longest renameable segment)" -ForegroundColor Green
    Write-Host "  L          → Rename the LEAF (segment $maxIdx)" -ForegroundColor White
    Write-Host "  S          → Skip this item" -ForegroundColor Yellow
    Write-Host "  Q          → Quit rename mode" -ForegroundColor Red
    Write-Host ""

    $userInput = Read-Host "Your choice"

    if ($userInput -match '^[Qq]$') {
        $quitRename = $true
        $processedIndices[$item.SharePointPath] = $true
        continue
    }
    if ($userInput -match '^[Ss]$') {
        $global:renameResults += [PSCustomObject]@{
            Timestamp=(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'); Type=$item.Type
            OriginalPath=$item.SharePointPath; OriginalLength=$item.PathLength
            RenamedSegment=""; OldSegmentName=""; NewSegmentName=""; NewPath=""; NewLength=0
            ItemsAffected=0; Status="Skipped"; ErrorMessage=""
        }
        $processedIndices[$item.SharePointPath] = $true
        continue
    }

    $targetSegIdx = -1
    if (:IsNullOrWhiteSpace($userInput)) {
        $candidates = $renamableSegs | Where-Object { -not $_.IsLeaf }
        if ($candidates.Count -eq 0) { $candidates = $renamableSegs }
        $best = $candidates | Sort-Object SegmentLength -Descending | Select-Object -First 1
        $targetSegIdx = $best.Index
        Write-Host ""
        Write-Host "🤖 Auto-fix chose segment [$targetSegIdx]: $($best.Name)" -ForegroundColor Cyan
    } elseif ($userInput -match '^[Ll]$') {
        $targetSegIdx = $maxIdx
    } elseif ($userInput -match '^\d+$') {
        $targetSegIdx = [int]$userInput
        if ($targetSegIdx -lt 1 -or $targetSegIdx -gt $maxIdx) {
            Write-Host "❌ Invalid segment number. Skipping." -ForegroundColor Red
            $processedIndices[$item.SharePointPath] = $true
            Start-Sleep -Seconds 1
            continue
        }
    } else {
        Write-Host "❌ Invalid choice." -ForegroundColor Red
        Start-Sleep -Seconds 1
        continue
    }

    $targetSeg = $segments | Where-Object { $_.Index -eq $targetSegIdx } | Select-Object -First 1
    if (-not $targetSeg) {
        Write-Host "❌ Segment not found." -ForegroundColor Red
        Start-Sleep -Seconds 1
        continue
    }

    Write-Host ""
    Write-Host "🎯 Selected segment [$targetSegIdx]: $($targetSeg.Name)" -ForegroundColor Cyan
    Write-Host "   Segment length    : $($targetSeg.SegmentLength) chars" -ForegroundColor Gray
    Write-Host "   Cumulative before : $($targetSeg.CumulativeLength - $targetSeg.SegmentLength - 1) chars" -ForegroundColor Gray

    $cumulativeBefore = $targetSeg.CumulativeLength - $targetSeg.SegmentLength - 1
    $effectiveParent  = if ($localSyncBasePath) { $localSyncBasePath.Length + 1 + $cumulativeBefore } else { $cumulativeBefore }
    $isFileSeg        = $targetSeg.IsLeaf -and ($item.Type -eq "File")
    $segItemType      = if ($isFileSeg) { "File" } else { "Folder" }
    $suggestion       = Get-SmartSuggestion -OriginalName $targetSeg.Name -ItemType $segItemType -ParentPathLength $effectiveParent -TargetMaxTotal ($global:criticalThreshold - 1)

    Write-Host ""
    Write-Host "💡 Suggested name : " -NoNewline -ForegroundColor Gray
    Write-Host $suggestion -ForegroundColor Green
    $savings = $targetSeg.SegmentLength - $suggestion.Length
    Write-Host "   Chars saved    : $savings chars per affected path" -ForegroundColor Cyan
    Write-Host ""

    $confirmed = $false
    $finalName = ""
    while (-not $confirmed) {
        $nameInput = Read-Host "New name for '$($targetSeg.Name)' (Enter = use suggestion, S = skip)"
        if ($nameInput -match '^[Ss]$') {
            $finalName = ""
            break
        }
        if (:IsNullOrWhiteSpace($nameInput)) { $finalName = $suggestion } else { $finalName = $nameInput.Trim() }

        $validation = Test-ValidSPName -Name $finalName
        if (-not $validation.Valid) {
            Write-Host "❌ $($validation.Reason)" -ForegroundColor Red
            continue
        }

        if ($isFileSeg) {
            $origExt = if ($targetSeg.Name.LastIndexOf('.') -gt 0) { $targetSeg.Name.Substring($targetSeg.Name.LastIndexOf('.')) } else { "" }
            $newExt  = if ($finalName.LastIndexOf('.') -gt 0) { $finalName.Substring($finalName.LastIndexOf('.')) } else { "" }
            if ($origExt -ne $newExt) {
                Write-Host "⚠️  Extension changing: $origExt → $newExt" -ForegroundColor Yellow
            }
        }

        $newSegName = $finalName
        $segs = $segments
        $oldPrefixParts = @()
        foreach ($s in $segs) {
            if ($s.IsRoot) { $oldPrefixParts += $s.Name; continue }
            $oldPrefixParts += $s.Name
            if ($s.Index -eq $targetSegIdx) { break }
        }
        if ($segs[0].IsRoot) {
            $oldPrefix = $oldPrefixParts[0] + "/" + ($oldPrefixParts[1..($oldPrefixParts.Count-1)] -join "/")
        } else {
            $oldPrefix = $oldPrefixParts -join "/"
        }
        $newPrefixParts = @($oldPrefixParts[0..($oldPrefixParts.Count - 2)]) + @($newSegName)
        if ($segs[0].IsRoot) {
            $newPrefix = $newPrefixParts[0] + "/" + ($newPrefixParts[1..($newPrefixParts.Count-1)] -join "/")
        } else {
            $newPrefix = $newPrefixParts -join "/"
        }
        $newFullPath = $newPrefix + $item.SharePointPath.Substring($oldPrefix.Length)
        $newLen      = if ($localSyncBasePath) { ($localSyncBasePath + "/" + $newFullPath).Length } else { $newFullPath.Length }
        $previewColor = if ($newLen -lt $global:warningThreshold) { "Green" } elseif ($newLen -lt $global:criticalThreshold) { "Yellow" } else { "Red" }

        $affectedCount = ($global:results | Where-Object {
            $_.SharePointPath -eq $oldPrefix -or $_.SharePointPath.StartsWith($oldPrefix + "/")
        }).Count

        Write-Host ""
        Write-Host "📋 Preview:" -ForegroundColor Cyan
        Write-Host "   Rename     : '$($targetSeg.Name)' → '$finalName'" -ForegroundColor White
        Write-Host "   This item  : $newFullPath" -ForegroundColor White
        Write-Host "   New length : $newLen chars" -ForegroundColor $previewColor
        Write-Host "   Affects    : $affectedCount item(s) under this folder" -ForegroundColor Cyan
        Write-Host ""
        $confirm = Read-Host "Confirm rename? (Y/N/E to edit)"
        if ($confirm -match '^[Yy]') { $confirmed = $true }
        elseif ($confirm -match '^[Ee]') { continue }
        else { $finalName = ""; break }
    }

    if (:IsNullOrWhiteSpace($finalName)) {
        $global:renameResults += [PSCustomObject]@{
            Timestamp=(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'); Type=$item.Type
            OriginalPath=$item.SharePointPath; OriginalLength=$item.PathLength
            RenamedSegment=""; OldSegmentName=""; NewSegmentName=""; NewPath=""; NewLength=0
            ItemsAffected=0; Status="Skipped"; ErrorMessage=""
        }
        $processedIndices[$item.SharePointPath] = $true
        Write-Host "⏭️  Skipped." -ForegroundColor Yellow
        Start-Sleep -Milliseconds 600
        continue
    }

    Write-Host ""
    Write-Host "⏳ Renaming on SharePoint..." -ForegroundColor Yellow
    $result = Invoke-SegmentRename -CurrentFullPath $item.SharePointPath -Segments $segments -SegmentIndex $targetSegIdx -NewSegmentName $finalName -ItemType $item.Type

    if ($result.Success) {
        Write-Host "✅ Renamed successfully! Updated $($result.Affected) in-memory path(s)." -ForegroundColor Green
        $global:renameResults += [PSCustomObject]@{
            Timestamp=(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'); Type=$item.Type
            OriginalPath=$item.SharePointPath; OriginalLength=$item.PathLength
            RenamedSegment="[$targetSegIdx]"; OldSegmentName=$targetSeg.Name; NewSegmentName=$finalName
            NewPath=$result.NewPrefix; NewLength=$result.NewPrefix.Length
            ItemsAffected=$result.Affected; Status="Renamed"; ErrorMessage=""
        }
        Start-Sleep -Seconds 1
    } else {
        Write-Host "❌ Rename failed: $($result.Error)" -ForegroundColor Red
        $global:renameResults += [PSCustomObject]@{
            Timestamp=(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'); Type=$item.Type
            OriginalPath=$item.SharePointPath; OriginalLength=$item.PathLength
            RenamedSegment="[$targetSegIdx]"; OldSegmentName=$targetSeg.Name; NewSegmentName=$finalName
            NewPath=""; NewLength=0; ItemsAffected=0; Status="Failed"; ErrorMessage=$result.Error
        }
        $processedIndices[$item.SharePointPath] = $true
        Read-Host "Press Enter to continue"
    }
}

# =====================================================================================
# RENAME SUMMARY
# =====================================================================================
Clear-Host
Show-Banner
Write-Host ""
Write-Host "✅ Rename Session Complete!" -ForegroundColor Green
Write-Host ("═" * $consoleWidth) -ForegroundColor DarkGray

$renamedCnt = ($global:renameResults | Where-Object { $_.Status -eq 'Renamed' }).Count
$skippedCnt = ($global:renameResults | Where-Object { $_.Status -eq 'Skipped' }).Count
$failedCnt  = ($global:renameResults | Where-Object { $_.Status -eq 'Failed' }).Count
$totalAffected = ($global:renameResults | Where-Object { $_.Status -eq 'Renamed' } | Measure-Object -Property ItemsAffected -Sum).Sum

Write-Host "✅ Segments Renamed : $renamedCnt" -ForegroundColor Green
Write-Host "⏭️  Items Skipped    : $skippedCnt" -ForegroundColor Yellow
Write-Host "❌ Failed           : $failedCnt" -ForegroundColor Red
Write-Host "📊 Total paths affected by renames: $totalAffected" -ForegroundColor Cyan
$remainingCrit = ($global:results | Where-Object { $_.Status -eq 'Critical' }).Count
Write-Host "🔴 Remaining critical paths       : $remainingCrit" -ForegroundColor $(if ($remainingCrit -eq 0) { "Green" } else { "Red" })
Write-Host ""

if ($global:renameResults.Count -gt 0) {
    $global:renameResults | Export-Csv -Path $renameCsv -NoTypeInformation -Encoding UTF8
    Write-Host "📊 Rename report : $renameCsv" -ForegroundColor Cyan
}

if ($failedCnt -gt 0) {
    Write-Host ""
    Write-Host "❌ Failed Renames:" -ForegroundColor Red
    Write-Host ("─" * $consoleWidth) -ForegroundColor DarkGray
    foreach ($f in ($global:renameResults | Where-Object { $_.Status -eq 'Failed' })) {
        Write-Host "  [$($f.Type)] $($f.OriginalPath)" -ForegroundColor Red
        Write-Host "      Segment: $($f.OldSegmentName) → $($f.NewSegmentName)" -ForegroundColor DarkRed
        Write-Host "      Error: $($f.ErrorMessage)" -ForegroundColor DarkRed
    }
}

Write-Host ""
Write-Host ("═" * $consoleWidth) -ForegroundColor DarkGray
Write-Host "📊 Scan CSV    : $csvFile" -ForegroundColor Cyan
Write-Host "📘 Scan Log    : $logFile" -ForegroundColor Cyan
if ($global:renameResults.Count -gt 0) {
    Write-Host "📊 Rename CSV  : $renameCsv" -ForegroundColor Cyan
}
Write-Host ""
Disconnect-PnPOnline
Write-Host "🔌 Disconnected from SharePoint Online." -ForegroundColor Gray
Write-Host ""
Write-Host "💡 Tip: Re-run the scanner to verify all paths are within safe limits!" -ForegroundColor DarkCyan
Write-Host ""
