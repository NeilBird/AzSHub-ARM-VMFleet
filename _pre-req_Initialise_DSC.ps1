
# Set the location of the script directory, Default to script execution folder, in case script is executed from a different location
if([string]::IsNullOrWhiteSpace($script:MyInvocation.MyCommand.Path)){
    $ScriptDir = "."
} else {
    $ScriptDir = Split-Path $script:MyInvocation.MyCommand.Path
}
Set-Location -Path $ScriptDir

# Purpose: Copies custom dsc resource to modules folder
# Installs dependent 3 x DSC modules from the PSGallery

# check we are at the right location
Get-Item .\DSC\StackTestHarness -ErrorVariable dirError

if(-not $dirError)
{
	# delete existing and copy
    Remove-Item -Recurse -Force "C:\Program Files\WindowsPowerShell\Modules\StackTestHarness" -Confirm:$false
    Copy-Item -Recurse -Force -Path .\DSC\StackTestHarness -Destination "C:\Program Files\WindowsPowershell\Modules\" -Confirm:$false
} else {
    # throw error, as unable to copy custom dsc resource from the current location
    Throw "Error, the 'DSC\StackTestHarness' folder was not found, please change directory to the root of the 'ARM-VMFleet' folder."
}


Find-Module -Name xPendingReboot -Repository PSGallery | Install-Module
Find-Module -Name ComputerManagementDsc -Repository PSGallery | Install-Module
Find-Module -Name FileDownloadDSC -Repository PSGallery | Install-Module
