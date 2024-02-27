
# Requires Az modules to be installed for Azure Stack Hub:
# https://learn.microsoft.com/en-us/azure-stack/operator/powershell-install-az-module

# DiskSpd information
# https://github.com/microsoft/diskspd/blob/master/README.md
# https://github.com/Microsoft/diskspd/wiki
# https://github.com/Microsoft/diskspd/wiki/Command-line-and-parameters
# Example DiskSpd params, defaults to 64K block size, 100% random write / reads, 15 threads, 20GB test file, 1 hour duration, 64 outstanding I/Os, and XML output file
# Write test: -c20G -w100 -F15 -r -o64 -d3600 -Sh -Rxml
# Read test: -c20G -F15 -r -o64 -d3600 -Sh -Rxml
# Large area sequential concurrent writes: -c20G -w100 -F15 -T1b -s8b -o64 -d3600 -Sh -Rxml
# Large area sequential concurrent reads: -c20G -F15 -T1b -s8b -o64 -d3600 -Sh -Rxml

# -c100G -t32 -o64 -d4800 -w50 -Sh -Rxml

# Credentials for the VMs
$cred = Get-Credential -UserName "admin" -Message "VM Admin cred"

# Set the location of the script directory, Default to script execution folder
if([string]::IsNullOrWhiteSpace($script:MyInvocation.MyCommand.Path)){
    $ScriptDir = "."
} else {
    $ScriptDir = Split-Path $script:MyInvocation.MyCommand.Path
}
Set-Location -Path $ScriptDir

# Initialise the DSC configuration, this installs the required DCS resource modules locally.
.\_pre-req_Initialise_DSC.ps1

# Standard_F16s has 16 x vCPUs and can have up to 64 x data disks.
# Max time for DSC extension is 90 minutes, allowing 10 minutes spare, results in 80 minutes, which is 4800 seconds.
# Check Qutoas on Admin Portal for max resoruces allowed, cores, VMs, managed disks...etc
# 50 x 10GB data disks = 1000GB = 500GB per VM

# Requires authenticated session to Azure Stack Hub:

# Add-AzEnvironment -Name "AzureStackUser" -ArmEndpoint "https://management.region.fqdn" `
    # -GraphEndpoint "https://graph.region.fqdn" -GalleryEndpoint "https://gallery.region.fqdn" `
    # -KeyVaultEndpoint "https://keyvault.region.fqdn" -StorageEndpoint "https://blob.region.fqdn" `
    # -Suffix "region.fqdn" -AzureKeyVaultDnsSuffix "vault.region.fqdn" `
    # -AzureKeyVaultServiceEndpointResourceId "https://vault.region.fqdn"
    # $AuthEndpoint = (Get-AzEnvironment -Name "AzureStackUser").ActiveDirectoryAuthority.TrimEnd('/')

# $TenantId = (invoke-restmethod "$($AuthEndpoint)/$($AADTenantName)/.well-known/openid-configuration").issuer.TrimEnd('/').Split('/')[-1]
# Use Login-AzAccount -EnvironmentName "AzureStackUser" -TenantId $TenantId

[string]$GridViewTile = "Select the Subscription/Tenant ID to deploy the ARM VM Fleet to..."
try{
    $AzContext = (Get-AzSubscription -ErrorAction Stop | Out-GridView `
    -Title $GridViewTile `
    -PassThru)
} catch {
    Write-Host "Error: $_"
    Write-Host "Please ensure you are authenticated to the target Azure Stack Hub using Login-AzAccount"
    break
}

# Check Hub Compute Quotas before running the script, needs vCPU, VMs, Managed Disks resources
# VM deployment logs default to "C:\ARM-VMFleet-Logs\"

# start ARM-VMFleet
.\ARM_VMFleet.ps1 -initialise -cred $cred -totalVmCount 50 -pauseBetweenVmCreateInSeconds 5 -location '<location>' -vmsize 'Standard_F16s' `
    -storageUrlDomain 'blob.<region>.<fqdn>' -testParams '-c100G -t32 -o64 -d4800 -w50 -Sh -Rxml' -dataDiskSizeGb 10 `
     -resourceGroupNamePrefix 'VMfleet-' -password $cred.Password -dontDeleteResourceGroupOnComplete -vmNamePrefix 'iotest' `
     -dataDiskCount 30 -resultsStorageAccountName 'testharness'



