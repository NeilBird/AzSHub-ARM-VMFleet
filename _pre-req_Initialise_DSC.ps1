# script requires -RunAsAdministrator to copy custom dsc resource to modules folder
#Requires -RunAsAdministrator

# Set the location of the script directory, Default to script execution folder, in case script is executed from a different location
if([string]::IsNullOrWhiteSpace($script:MyInvocation.MyCommand.Path)){
    $ScriptDir = "."
} else {
    $ScriptDir = Split-Path $script:MyInvocation.MyCommand.Path
}
# Change the location to the script directory
Set-Location -Path $ScriptDir | Out-Null

# Purpose: Copies custom dsc resource to modules folder
# Installs dependent 3 x DSC modules from the PSGallery

# check we are at the right location
$DCSfolder = Get-Item .\DSC\StackTestHarness -ErrorVariable dirError

# Check if the folder exists and is a directory
if(-not($dirError) -and ($null -ne $DCSfolder) -and ($DCSfolder.PSIsContainer -eq $true))
{
	# delete existing and copy
    Write-Progress -Activity "DSC Step 1 - Custom DSC resource" -Status "Removing existing custom DSC resource" -PercentComplete 0
    Remove-Item -Recurse -Force "C:\Program Files\WindowsPowerShell\Modules\StackTestHarness" -Confirm:$false -Verbose -ErrorAction Stop
    Write-Progress -Activity "DSC Step 1 - Custom DSC resource" -Status "Copying custom DSC resource" -PercentComplete 33
    Copy-Item -Recurse -Force -Path .\DSC\StackTestHarness -Destination "C:\Program Files\WindowsPowershell\Modules\" -Confirm:$false -Verbose -ErrorAction Stop
} else {
    # throw error, as unable to copy custom dsc resource from the current location
    Throw "Error, the 'DSC\StackTestHarness' folder was not found, please change directory to the root of the 'ARM-VMFleet' folder."
}

# install dependent DSC modules
Write-Progress -Activity "DSC Step 2 - Installing dependent DSC modules" -Status "Installing xPendingReboot" -PercentComplete 66
Find-Module -Name xPendingReboot -Repository PSGallery | Install-Module
Write-Progress -Activity "DSC Step 2 - Installing dependent DSC modules" -Status "Installing ComputerManagementDsc" -PercentComplete 75
Find-Module -Name ComputerManagementDsc -Repository PSGallery | Install-Module
Write-Progress -Activity "DSC Step 2 - Installing dependent DSC modules" -Status "Installing FileDownloadDSC" -PercentComplete 100
Find-Module -Name FileDownloadDSC -Repository PSGallery | Install-Module
