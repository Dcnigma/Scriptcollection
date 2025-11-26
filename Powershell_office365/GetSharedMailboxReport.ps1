# Install module if needed
if (-not (Get-Module -ListAvailable -Name ExchangeOnlineManagement)) {
    Install-Module ExchangeOnlineManagement -Force
}

Import-Module ExchangeOnlineManagement

# Connect to Exchange Online
Connect-ExchangeOnline

# Output file
$OutputFile = "./AllSharedMailboxes_Members_With_Stats.csv"

# Use a List for AddRange support (PowerShell 7 safe)
$Results = New-Object System.Collections.Generic.List[object]

# Function to resolve display name
function Resolve-DisplayName {
    param([string]$Identity)

    try {
        $user = Get-Recipient -Identity $Identity -ErrorAction Stop
        return $user.DisplayName
    }
    catch {
        return "Unknown"
    }
}

# System accounts filter function
function Is-RealUser {
    param($Identity)

    return !(
        $Identity -match "NT AUTHORITY" -or
        $Identity -match "^S-1-5-" -or
        $Identity -eq "SELF" -or
        $Identity -eq "SYSTEM"
    )
}

# Get all shared mailboxes
$SharedMailboxes = Get-Mailbox -RecipientTypeDetails SharedMailbox -ResultSize Unlimited

foreach ($mbx in $SharedMailboxes) {

    $MailboxName = $mbx.PrimarySmtpAddress.ToString()
    Write-Host "Processing mailbox: $MailboxName" -ForegroundColor Cyan

    # ---- Mailbox stats ----
    $Stats = Get-MailboxStatistics -Identity $MailboxName
    $ItemCount   = $Stats.ItemCount
    $TotalSize   = $Stats.TotalItemSize.ToString()

    # Quotas from mailbox object
    $ProhibitSendQuota = $mbx.ProhibitSendQuota
    $IssueWarningQuota = $mbx.IssueWarningQuota
    $UseMailboxQuota   = $mbx.UseDatabaseQuotaDefaults

    # ---- Full Access ----
    $FA = Get-MailboxPermission -Identity $MailboxName |
        Where-Object { Is-RealUser $_.User } |
        ForEach-Object {
            $UPN = $_.User.ToString()
            [pscustomobject]@{
                Mailbox          = $MailboxName
                UserPrincipal    = $UPN
                DisplayName      = Resolve-DisplayName $UPN
                Permission       = "FullAccess"
                ItemCount        = $ItemCount
                TotalSize        = $TotalSize
                ProhibitSendQuota= $ProhibitSendQuota
                IssueWarningQuota= $IssueWarningQuota
                UseMailboxQuota  = $UseMailboxQuota
            }
        }

    # ---- SendAs ----
    $SA = Get-RecipientPermission -Identity $MailboxName |
        Where-Object { Is-RealUser $_.Trustee } |
        ForEach-Object {
            $UPN = $_.Trustee.ToString()
            [pscustomobject]@{
                Mailbox          = $MailboxName
                UserPrincipal    = $UPN
                DisplayName      = Resolve-DisplayName $UPN
                Permission       = "SendAs"
                ItemCount        = $ItemCount
                TotalSize        = $TotalSize
                ProhibitSendQuota= $ProhibitSendQuota
                IssueWarningQuota= $IssueWarningQuota
                UseMailboxQuota  = $UseMailboxQuota
            }
        }

    # ---- SendOnBehalf ----
    $SOB = $mbx.GrantSendOnBehalfTo |
        Where-Object { Is-RealUser $_ } |
        ForEach-Object {
            $UPN = $_.ToString()
            [pscustomobject]@{
                Mailbox          = $MailboxName
                UserPrincipal    = $UPN
                DisplayName      = Resolve-DisplayName $UPN
                Permission       = "SendOnBehalf"
                ItemCount        = $ItemCount
                TotalSize        = $TotalSize
                ProhibitSendQuota= $ProhibitSendQuota
                IssueWarningQuota= $IssueWarningQuota
                UseMailboxQuota  = $UseMailboxQuota
            }
        }

    # ---- Make sure all are arrays for AddRange ----
    $FA  = @($FA)
    $SA  = @($SA)
    $SOB = @($SOB)

    # ---- Add to master list ----
    $Results.AddRange($FA)
    $Results.AddRange($SA)
    $Results.AddRange($SOB)
}

# Export final CSV
$Results | Export-Csv -Path $OutputFile -NoTypeInformation -Encoding UTF8

Write-Host "`nDone!" -ForegroundColor Green
Write-Host "Export saved to: $OutputFile`n"
