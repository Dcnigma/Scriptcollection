#Check if SharePoint Online PnP PowerShell module has been installed
Try {
    Write-host "Checking if SharePoint Online PnP PowerShell Module is Installed..." -f Yellow -NoNewline
    $PnPPowerShell= Get-Module -ListAvailable "PnP.PowerShell"
 
    If(!$PnPPowerShell)
    {
        Write-host "No!" -f Green
 
        #Check if script is executed under elevated permissions - Run as Administrator
        If (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator"))
        {   
            Write-Host "Please Run this script in elevated mode (Run as Administrator)! " -NoNewline
            Read-Host "Press any key to continue"
            Exit
        }
 
        Write-host "Installing SharePoint Online PnP PowerShell Module..." -f Yellow -NoNewline
        Install-Module PnP.PowerShell -Force -Confirm:$False
        Write-host "Done!" -f Green
    }
    Else
    {
        Write-host "Yes!" -f Green
        Write-host "Importing SharePoint Online PnP PowerShell Module..." -f Yellow  -NoNewline
        Import-Module PnP.PowerShell -DisableNameChecking
        Write-host "Done!" -f Green
    }
}
Catch{
    write-host "Error: $($_.Exception.Message)" -foregroundcolor red
}