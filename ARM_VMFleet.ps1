##########################################################################################################
<#
.SYNOPSIS
    Author:     Neil Bird, MSFT
    Version:    0.4.5
    Created:    11th October 2022
    Updated:    5th March 2024

.DESCRIPTION
  
    This script automates the creation of virtual machines using ARM and the Az PowerShell modules.
    Once created, each VM executes the DSC Extension to run a custom resource to create a virtual disk using
    Storage Spaces, to create a Striped Virtual Disk (RAID Zero). And finally, DiskSpd is used to generate 
    IO load on the striped disk, which is the F:\ drive inside the VM Guest OS. PerfMon is enabled inside the 
    Guest OS before the test, and stopped afterwards, and the BLG output is copied to a central storage account.

.EXAMPLE

    # Requires authenticated session to Azure Stack Hub management (ARM) endpoint:
    .\_pre-req_Example_Connect_ARM.ps1

    # Hub region name / location:
    $location = $((Get-AzLocation).location)
    # StorageEndpointSuffix, used for storage account blob creation:
    $storageEndpointSuffix = $((Get-AzEnvironment (Get-AzContext).Environment).StorageEndpointSuffix)
    
    # Create a credential object for the VMs:
    $cred = Get-Credential -UserName "admin" -Message "VM Admin cred"
    
    # start ARM-VMFleet:
    .\ARM_VMFleet.ps1 -initialise -cred $cred -totalVmCount 25 -pauseBetweenVmCreateInSeconds 5 -location $location -vmsize 'Standard_F8s' `
        -storageUrlDomain "blob.$storageEndpointSuffix" -testParams '-c100G -t32 -o64 -d2700 -W900 -w50 -Sh -Rxml' -dataDiskSizeGb 10 `
        -resourceGroupNamePrefix 'VMfleet-' -dontDeleteResourceGroupOnComplete -vmNamePrefix 'iotest' `
        -dataDiskCount 30 -resultsStorageAccountName 'vmfleetresults'

     Consideration, it is possible to hit the ARM Write limit of 1200 per 60 minutes per subscription, if you have a
     large number of VMs (50+) and data disks (30+). An error would be shown in the Activity log in the Azure Stack Hub User Portal.

.NOTES
    THIS CODE-SAMPLE IS PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER EXPRESSED 
    OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE IMPLIED WARRANTIES OF MERCHANTABILITY AND/OR 
    FITNESS FOR A PARTICULAR PURPOSE.

    This sample is not supported under any Microsoft standard support program or service. 
    The script is provided AS IS without warranty of any kind. Microsoft further disclaims all
    implied warranties including, without limitation, any implied warranties of merchantability
    or of fitness for a particular purpose. The entire risk arising out of the use or performance
    of the sample and documentation remains with you. In no event shall Microsoft, its authors,
    or anyone else involved in the creation, production, or delivery of the script be liable for 
    any damages whatsoever (including, without limitation, damages for loss of business profits, 
    business interruption, loss of business information, or other pecuniary loss) arising out of 
    the use of or inability to use the sample or documentation, even if Microsoft has been advised 
    of the possibility of such damages, rising out of the use of or inability to use the sample script, 
    even if Microsoft has been advised of the possibility of such damages. 

#>
##########################################################################################################

# Require PowerShell v5.0 and above
#Requires -Version 5
# Require Az module, check for Az.Compute, but many other, such as Az.Accounts are required.
#Requires -Module @{ ModuleName = 'Az.Compute'; ModuleVersion = '3.3.0' }

<#
Additional notes:
    Script framework and automation updated by Neil Bird in October 2022, updated February 2024
    Updated to Az module, added loop for data disks, fixed DSC failure, rev'ed extension version,
    Updated to use Managed Disks, and added switch for unmanaged
    Orinigal "DiskSpdTest" DSC resource module created by Matt Cowen, August 2018
    Creates virtual machines in parallel each in their own resource group and runs performance tests
    outputting the results to blob storage. It then deletes each resource group once the test is complete.
#>

[CmdletBinding()]
Param
(
    [parameter(Mandatory=$True)]
    [PSCredential]$cred, # the credentials to use for the VMs
	[string]$resourceGroupNamePrefix = 'VMFleet-', # the prefix for the resource group names
    [ValidateLength(3,10)]
    [parameter(Mandatory=$True)]
    [string]$location, # the location to create the VMs in, this is the "region" in Azure Stack Hub
    [string]$logfilefolder = "C:\ARM-VMFleet-Logs\", # output folder for logs of VMs
    [string]$resultsStorageAccountName = 'vmfleetresults', # where the results from performance counters are saved
    [string]$resultsStorageAccountRg = 'ARM-VMFleet',
	[string]$keyVaultName = 'VMFleetVault-'+([System.Guid]::NewGuid().ToString().Replace('-', '').substring(0, 8)),
    [string]$vnetName = 'VMFleet-vNet',  # the name of the vnet to add the VMs to (must match what is set in the ARM template)
    [string]$AccountType = "Standard_LRS", # could use "Premium_LRS", but does not change disk IOPs QoS policy in Hub, this is a factor of the VM size
    [string]$artifactsContainerName = 'artifacts',  # the container for uploading the published DSC configuration
    [int32]$pauseBetweenVmCreateInSeconds = 0, # the number of seconds to pause between creating VMs
    [int32]$totalVmCount = 5, # the number of VMs to create
    [System.IO.FileInfo]$diskSpd = ".\DiskSpd.ZIP", # the path to the DiskSpd archive, this is in the root of the scripts folder

	[ValidateLength(3,20)]
	[string]$vmNamePrefix = 'iotest', # DO NOT USE CHARS SUCH AS HYPHENS, as this is used for Storage Container name.
	[string]$vmsize = 'Standard_D2s_v3',   # the size of VM to create
    [string]$testParams = '-c20G -t15 -o128 -d3600 -w50 -Rxml', # the parameters for DiskSpd, default block size is 64K
    [string]$dscPath = '.\DSC\DiskPrepTest.ps1',     # the path to the DSC configuration to run on the VMs
    [ValidateLength(6,100)]
    [parameter(Mandatory=$True)]
    [string]$storageUrlDomain, # the domain of the storage account, e.g. "blob.<region>.<fqdn>"
	[int32]$dataDiskSizeGb = 10, # size of data disks to add to each VM
    [int32]$dataDiskCount = 4, # count of data disks to add to each VM, these are added to a Stripe 0 in Storage Spaces, VM size must support number of data disks.
    [switch]$dontDeleteResourceGroupOnComplete, # switch to not delete the resource group on completion, useful for debugging
	[switch]$dontPublishDscBeforeStarting, # switch to not publish the DSC before starting the VMs, useful for debugging
	[switch]$initialise, # needed for initial deployment to create vnet
    [switch]$UseUnmanagedDisks # switch to use UnmanagedDisks, default to Managed Disks without this present.

)
Write-Host "Started at $(Get-Date -Format 'HH:mm:ss')"

# define this as boolean, due to splatting with parameters in job.
if($UseUnmanagedDisks.IsPresent){
    $UseUnmanagedDisks = $true
} else {
    $UseUnmanagedDisks = $false
}


if(-not (Test-Path $dscPath)){
	Write-Host "Can't find necessary files. Are you at the right location?"
	exit
}

Enable-AzContextAutosave
# If Initialise switch passed
if($initialise.IsPresent){

    Write-Host "Initialise is set to $initialise`n"

    # Register required Resource Providers:
    Write-Progress -Activity "Initialising Subscirption Prerequisites" -Status "Registering Resource Providers" -PercentComplete 0
    Write-Host "Registering Resource Providers in subscription $((Get-AzContext).Subscription.Name)" -ForegroundColor Yellow
    Write-Progress -Activity "Initialising Subscirption Prerequisites" -Status "Registering Microsoft.Resources" -PercentComplete 6
    Register-AzResourceProvider -ProviderNamespace Microsoft.Resources -Verbose -ErrorAction Stop
    Write-Progress -Activity "Initialising Subscirption Prerequisites" -Status "Registering Microsoft.Storage" -PercentComplete 12
    Register-AzResourceProvider -ProviderNamespace Microsoft.Storage -Verbose -ErrorAction Stop
    Write-Progress -Activity "Initialising Subscirption Prerequisites" -Status "Registering Microsoft.Network" -PercentComplete 18
    Register-AzResourceProvider -ProviderNamespace Microsoft.Network -Verbose -ErrorAction Stop
    Write-Progress -Activity "Initialising Subscirption Prerequisites" -Status "Registering Microsoft.Compute" -PercentComplete 24
    Register-AzResourceProvider -ProviderNamespace Microsoft.Compute -Verbose -ErrorAction Stop
    Write-Progress -Activity "Initialising Subscirption Prerequisites" -Status "Registering Microsoft.KeyVault" -PercentComplete 28
    Register-AzResourceProvider -ProviderNamespace Microsoft.KeyVault -Verbose -ErrorAction Stop

    Write-Host "Creating resources to receive test results/output" -ForegroundColor Yellow
    Write-Host "- creating resource group $resultsStorageAccountRg on $location" -ForegroundColor Yellow
    Write-Progress -Activity "Initialising Subscirption Prerequisites" -Status "Creating Resource Group" -PercentComplete 34
    New-AzResourceGroup -Name $resultsStorageAccountRg -Location $location -ErrorAction Stop
    
    Write-Host "- creating storage account Storage Account: $resultsStorageAccountName  Resource Group: $resultsStorageAccountRg" -ForegroundColor Yellow
    Write-Progress -Activity "Initialising Subscirption Prerequisites" -Status "Creating Storage Account" -PercentComplete 40
    $resultsStdStore = New-AzStorageAccount -ResourceGroupName $resultsStorageAccountRg -Name $resultsStorageAccountName `
    -Location $location -Type $AccountType -ErrorAction Stop
    
    Write-Host "- creating artifacts containers" -ForegroundColor Yellow
    Write-Progress -Activity "Initialising Subscirption Prerequisites" -Status "Creating DSC Artifacts Container" -PercentComplete 46
    New-AzStorageContainer -Name $artifactsContainerName -Context $($resultsStdStore.Context) -ErrorAction Stop

    # upload DiskSpd-2.1.zip to artifacts
    Write-Host "- uploading diskspd archive" -ForegroundColor Yellow
    Write-Progress -Activity "Initialising Subscirption Prerequisites" -Status "Uploading DiskSpd.zip Archive" -PercentComplete 52 
    Set-AzStorageBlobContent -File $diskSpd -Blob 'DiskSpd.ZIP' -Container $artifactsContainerName -Context $resultsStdStore.Context -Verbose -Force -ErrorAction Stop
    # Remove write progress bar from Set-AzStorageBlobContent output
    Write-Progress -Completed
    
    Write-Host "- creating key vault" -ForegroundColor Yellow
    Write-Progress -Activity "Initialising Subscirption Prerequisites" -Status "Creating Key Vault" -PercentComplete 58
    New-AzKeyVault -VaultName $keyVaultName -ResourceGroupName $resultsStorageAccountRg -Location $location -ErrorAction Stop

    # Creator / owner can set all access policies, but we need to set the current user to have explicit access to the key vault
    Write-Host "- setting access policy for $((get-azcontext).Account.Id) on key vault"  -ForegroundColor Yellow
    Write-Progress -Activity "Initialising Subscirption Prerequisites" -Status "Setting KeyVault Access Policy" -PercentComplete 64
    Set-AzKeyVaultAccessPolicy -VaultName $keyVaultName -ResourceGroupName $resultsStorageAccountRg -EmailAddress $((get-azcontext).Account.Id) -PermissionsToKeys get,create,import,delete,list,update -PermissionsToSecrets get,set,delete,list,recover,backup,restore,purge -PassThru -ErrorAction SilentlyContinue
    
    Write-Host "- adding secrets to key vault..." -ForegroundColor Yellow
    Write-Progress -Activity "Initialising Subscirption Prerequisites" -Status "Adding VM Password Secret to KeyVault" -PercentComplete 70
    # ConvertTo-SecureString -AsPlainText -Force
    $Password = ConvertTo-SecureString -String $cred.GetNetworkCredential().Password -AsPlainText -Force
    # Add password secret to key vault
    Set-AzKeyVaultSecret -VaultName $keyVaultName -Name 'password' -SecretValue $Password | Out-Null
    # ConvertTo-SecureString -AsPlainText -Force
    $Username = ConvertTo-SecureString -String $cred.GetNetworkCredential().UserName -AsPlainText -Force
    # Add username secret to key vault
    Write-Progress -Activity "Initialising Subscirption Prerequisites" -Status "Adding VM Username Secret to KeyVault" -PercentComplete 76
    Set-AzKeyVaultSecret -VaultName $keyVaultName -Name 'username' -SecretValue $Username | Out-Null
    $accKey = Get-AzStorageAccountKey -ResourceGroupName $resultsStorageAccountRg -AccountName $resultsStorageAccountName -ErrorAction Stop
    # Add storage key to key vault
    Write-Progress -Activity "Initialising Subscirption Prerequisites" -Status "Adding Storage Account Key Secret to KeyVault" -PercentComplete 82
    Set-AzKeyVaultSecret -VaultName $keyVaultName -Name 'storageKey' -SecretValue (ConvertTo-SecureString $accKey.Value[0] -AsPlainText -Force)

    Write-Host "Resources ready for ARM VM Fleet automation..."-ForegroundColor Yellow

    # check if virtual network already exists, if not create it
    Write-Host "Creating Virtual Network"
    Write-Progress -Activity "Initialising Subscirption Prerequisites" -Status "Creating Virtual Network Subnet" -PercentComplete 88
    $frontendSubnet = New-AzVirtualNetworkSubnetConfig -Name 'Subnet' -AddressPrefix "10.0.1.0/24"
    Write-Progress -Activity "Initialising Subscirption Prerequisites" -Status "Creating Virtual Network" -PercentComplete 92
    New-AzVirtualNetwork -Name $vnetName -ResourceGroupName $resultsStorageAccountRg -Location $location -AddressPrefix "10.0.0.0/16" -Subnet $frontendSubnet -Force -Confirm:$false -ErrorAction Stop
    Write-Host "Virtual Network created" -ForegroundColor Yellow

} # end initialise

# Check if Virtual Network exists, if not create it
$TestVirtualNetwork = Get-AzVirtualNetwork -Name $vnetName -ResourceGroupName $resultsStorageAccountRg -ErrorVariable VirtualNetworkError -ErrorAction SilentlyContinue
if($VirtualNetworkError){
    Write-Host "Creating Virtual Network"
    $frontendSubnet = New-AzVirtualNetworkSubnetConfig -Name 'Subnet' -AddressPrefix "10.0.1.0/24"
    New-AzVirtualNetwork -Name $vnetName -ResourceGroupName $resultsStorageAccountRg -Location $location -AddressPrefix "10.0.0.0/16" -Subnet $frontendSubnet -Force -Confirm:$false -ErrorAction Stop

} else {
    # Check Results Resoruce Group exists, if not stop, as needed to Initialise and switch was not passed
    Get-AzResourceGroup -Name $resultsStorageAccountRg -ErrorVariable resultsRgNotPresent -ErrorAction SilentlyContinue
    if($resultsRgNotPresent){
        Write-Host "Info: '-initialise' switch was NOT passed in parameters, however the $resultsStorageAccountRg Resource Group does NOT exist, exiting...."
        Write-Error "Prerequisite resources NOT present for ARM VM Fleet automation, re-run with -initialise"
        Exit
    }
}

# Get current working directory, to append to vm log file.
$root = Get-Location
Write-Host "Get Storage Account context to store test results..."
$resultsStorage = Get-AzStorageAccount -ResourceGroupName $resultsStorageAccountRg -Name $resultsStorageAccountName -ErrorAction Stop

if(-not $dontPublishDscBeforeStarting){
	Write-Host "Publishing DSC"
    Write-Progress -Activity "Initialising Subscirption Prerequisites" -Status "Publishing Custom DSC Resource" -PercentComplete 96
	# we need to publish the dsc to the root of the "artifacts" container:
    Publish-AzVMDscConfiguration -ConfigurationPath $dscPath -ResourceGroupName $resultsStorageAccountRg `
		-StorageAccountName $resultsStorageAccountName -ContainerName $artifactsContainerName -Force -Verbose -ErrorAction Stop
}

Write-Progress -Activity "Initialising Subscirption Prerequisites" -Status "Initialisation complete" -PercentComplete 100

$storageKey = (Get-AzStorageAccountKey -ResourceGroupName $resultsStorageAccountRg -AccountName $resultsStorageAccountName -ErrorAction Stop).Value[0] +''

$diskSpdDownloadUrl = New-AzStorageBlobSASToken -Blob 'DiskSpd.ZIP' -Container $artifactsContainerName -FullUri -Context $resultsStorage.Context -Permission r -ExpiryTime (Get-Date).AddHours(24)

Write-Verbose "`nDiskSpd download url: $diskSpdDownloadUrl"


# Loop to create VMs
for ($x = 1; $x -le $totalVmCount; $x++)
{

    Write-Progress -Activity "Deploying ARM VM Fleet:" -Status "Creating VM $x of $totalVmCount..." -PercentComplete $(($x / $totalVmCount) * 100)

    $resourceGroup = $resourceGroupNamePrefix + "{0:D3}" -f $x

    Write-Host "Starting creation of vm: $($vmNamePrefix + "{0:D3}" -f $x) in resource group: $resourceGroup..."
    $resultsContainerName = $($vmNamePrefix + "{0:D3}" -f $x).ToLower()

    $params = @(
        $resourceGroup
		$root
        $logfilefolder
        $storageKey
		$vmNamePrefix
        $vmsize
		$vnetName
        $AccountType
		$dataDiskSizeGb
        $dataDiskCount
        $cred
        $x
        $location
		$diskSpdDownloadUrl
        $UseUnmanagedDisks
		$testParams
		$resultsStorage
        $resultsStorageAccountRg
		$resultsStorageAccountName
		$resultsContainerName
		$artifactsContainerName
		$dscPath
		$storageUrlDomain
		$dontDeleteResourceGroupOnComplete
    )

    $job = Start-Job -ScriptBlock { 
        param(
            $resourceGroup,
			$root,
            $logfilefolder,
            $storageKey,
			$vmNamePrefix,
            $vmsize,
			$vnetName,
            $AccountType,
			$dataDiskSizeGb,
            $dataDiskCount,
            [PSCredential] $cred, 
            $x, 
            $location,
			$diskSpdDownloadUrl,
            $UseUnmanagedDisks,
			$testParams,
			$resultsStorage,
            $resultsStorageAccountRg,
			$resultsStorageAccountName,
			$resultsContainerName,
			$artifactsContainerName,
			$dscPath,
			$storageUrlDomain,
			$dontDeleteResourceGroupOnComplete

        )
        $vmName = $($vmNamePrefix + "{0:D3}" -f $x)
        $testName = "$vmNamePrefix"
        $sw = [Diagnostics.Stopwatch]::StartNew()
        # If the log directory does not exist, create it
        if(-not(Test-Path $logfilefolder)){
            New-Item -ItemType Directory -Force -Path $logfilefolder -ErrorAction Stop
        }
        $log = "$logfilefolder\$vmName.log"
        Add-content $log "starting,$(Get-Date -Format 'yyyy-M-d HH:mm:ss')"
		Set-Location -Path $root -PassThru | Out-File -FilePath $log -Append -Encoding utf8
        

        Get-azResourceGroup -Name $resourceGroup -ErrorVariable notPresent -ErrorAction SilentlyContinue

        if ($notPresent)
        {
            Add-content $log "creating resource group: $resourceGroup"
            New-AzResourceGroup -Name $resourceGroup -Location $location -ErrorAction Stop
        }

        Add-content $log "creating VM storage,$($sw.Elapsed.ToString())"
        
        if($UseUnmanagedDisks) # switch to use UnmanagedDisks, creates a storage account to store VHDs
        {
            # Create storage account to store VHD disks per VM
            $vmStorageAccountName = 'vm'+ ([System.Guid]::NewGuid().ToString().Replace('-', '').substring(0, 19))
            Add-content $log "Unmanaged Disks Storage Account Name:  $vmStorageAccountName"
            $vmStore = New-AzStorageAccount -ResourceGroupName $resourceGroup -Name $vmStorageAccountName `
            -Location $location -Type $AccountType -ErrorAction Stop
        }

        # Storage account used for optional, upload / download of file speed tests
        $stdStorageAccountName = 'std'+ ([System.Guid]::NewGuid().ToString().Replace('-', '').substring(0, 19))
        Add-content $log "creating storage account for network speed tests: $stdStorageAccountName,$($sw.Elapsed.ToString())"
        $stdStore = New-AzStorageAccount -ResourceGroupName $resourceGroup -Name $stdStorageAccountName `
        -Location $location -Type $AccountType
        New-AzStorageContainer -Name $testName -Context $($stdStore.Context) -ErrorAction Stop
        # Create SAS token for the container to use for upload / download tests
        $fileUploadTestSasToken = New-AzStorageContainerSASToken -Container $testName -FullUri -Context $stdStore.Context -Permission rw -ExpiryTime (Get-Date).AddHours(24)

		# add a new container to $resultsStorageAccountName storage account, to upload the PerfMon BLG and DiskSpd output per VM
        $resultsStorage = Get-AzStorageAccount -ResourceGroupName $resultsStorageAccountRg -Name $resultsStorageAccountName -ErrorAction Stop
        Add-content $log "creating VM container in results storage account,$($sw.Elapsed.ToString())"
		New-AzStorageContainer -Name $vmName.ToLower() -Context $($resultsStorage.Context) -ErrorAction Stop
        
        # Create SAS token for the container to upload the PerfMon BLG and DiskSpd output
        $uploadSasToken = New-AzStorageContainerSASToken -Container $vmName.ToLower() -FullUri -Context $resultsStorage.Context -Permission rw -ExpiryTime (Get-Date).AddHours(24)
        
        Add-content $log "creating virtual nic,$($sw.Elapsed.ToString())"

        # Get the virtual network and subnet, to create the vNIC
        $Vnet = Get-AzVirtualNetwork -Name $vnetName -ResourceGroupName $resultsStorageAccountRg
        $SingleSubnet = Get-AzVirtualNetworkSubnetConfig -Name 'Subnet' -VirtualNetwork $Vnet

        $nicCreateCount = 4
        do{
            # Retry loop, in case nic creation fails:
            $NIC = New-AzNetworkInterface -Name "$vmName-nic1" -ResourceGroupName $resourceGroup -Location $location -SubnetId $Vnet.Subnets[0].Id -Force -ErrorAction SilentlyContinue -ErrorVariable nicCreateError
            $nicCreateCount -= 1
            
			if($nicCreateError){
				Add-content $log "$vmName-nic1 create,$nicCreateError,$($sw.Elapsed.ToString())"
			}
			Start-Sleep -Seconds 10
        }
        while($nicCreateError -or $nicCreateCount -eq 0)
        
        Add-content $log "creating vm object, $($sw.Elapsed.ToString())"
        $VirtualMachine = New-AzVMConfig -VMName $vmName  -VMSize $vmsize    
        
        Add-content $log "creating $($dataDiskCount) x data disks,$($sw.Elapsed.ToString())"
        # Loop to create data disks using $dataDiskCount and $dataDiskSizeGb parameters
        ForEach($i in 1..$dataDiskCount){
            [int]$lun = $i - 1
            # generate data disk name and format $i to two digit
            $DataDiskName = "Data" + "{0:D2}" -f $i
            if($UseUnmanagedDisks) # switch to use UnmanagedDisks
            {
                # Single line for Unmanaged Disks
                $VirtualMachine = Add-AzVMDataDisk -VM $VirtualMachine -Name $DataDiskName -Lun $lun -CreateOption Empty -DiskSizeInGB $dataDiskSizeGb -VhdUri "https://$vmStorageAccountName.$storageUrlDomain/vhds/$vmName-$DataDiskName.vhd" -Caching None
            } else {
                # Managed Disk configuraion:
                $DiskConfig = New-AzDiskConfig -AccountType $AccountType -Location $location -DiskSizeGB $dataDiskSizeGb -CreateOption Empty
                # Create managed disk.
                $Disk = New-AzDisk -DiskName $DataDiskName -Disk $DiskConfig -ResourceGroupName $resourceGroup -Verbose
                # Add managed disk to VM config
                Add-AzVMDataDisk -VM $VirtualMachine -Name $DataDiskName -Lun $lun -CreateOption Attach -ManagedDiskId $Disk.Id -Caching None -ErrorVariable DataDiskError
                if($DataDiskError){
                    Add-content $log "adding disk $DataDiskName failed after $($sw.Elapsed.ToString()), result: $DataDiskError"
                }
            }
        } # end loop for each data disk
        
        # Disable BootDiagnostics
        $VirtualMachine = Set-AzVMBootDiagnostic -VM $VirtualMachine -Disable
        # Set OS type and credentials
        $VirtualMachine = Set-AzVMOperatingSystem -VM $VirtualMachine -Windows -ComputerName $vmName -Credential $cred 
        
        Add-content $log "creating os disk, $($sw.Elapsed.ToString())"        
        # Define OS image Publisher, Offer, SKU and version
        $VirtualMachine = Set-AzVMSourceImage -VM $VirtualMachine -PublisherName "MicrosoftWindowsServer" -Offer "WindowsServer" -Skus "2019-Datacenter" -Version "latest"
        
        # OS Disk creation
        if($UseUnmanagedDisks){
            # Unmanaged Disk using storage account
            $VirtualMachine = Set-AzVMOSDisk -VM $VirtualMachine -Name 'OsDisk' -VhdUri "https://$vmStorageAccountName.$storageUrlDomain/vhds/$vmName-OsDisk.vhd" -CreateOption 'FromImage'
        } else { # Default to Managed Disks
            # Managed Disk
            $VirtualMachine = Set-AzVMOSDisk -VM $VirtualMachine -Name 'OsDisk' -CreateOption 'FromImage'
        }

        # Add vNIC
        $VirtualMachine = Add-AzVMNetworkInterface -VM $VirtualMachine -Id $NIC.Id

		### create the VM ###
        Add-content $log "starting ARM deployment of vm: $vmName, $($sw.Elapsed.ToString())"
        $vmresult = New-AzVM -VM $VirtualMachine -ResourceGroupName $resourceGroup -Location $location -ErrorVariable vmOutput -Verbose
        
        # Output any VM creation failure reason:
        if($vmOutput){
            Add-content $log "vm deployment failed, result: $vmOutput"
        }

        # VM Creation Successful:
        if($vmresult.IsSuccessStatusCode){
            Add-content $log "= = = = = = = = = ="
            Add-content $log "vmName = $vmName"
            Add-content $log "VM created successfully,$($sw.Elapsed.ToString())"
	        Add-content $log "diskspddownloadurl = $diskSpdDownloadUrl"
            Add-content $log "uploadSasToken  = $uploadSasToken"
	        Add-content $log "testParams = $testParams"
            Add-content $log "testName = $testName"
            Add-content $log "storageKey = $storageKey"
            Add-content $log "resultsContainerName = $resultsContainerName"
            Add-content $log "resultsStorageAccountName = $resultsStorageAccountName"
            Add-content $log "storageUrlDomain = $storageUrlDomain"
            Add-content $log "uploadSasToken = $uploadSasToken"
            Add-content $log "artifactsContainerName = $artifactsContainerName"
            Add-content $log "resourceGroup = $resourceGroup"

            # DSC parameters
            $dscConfigParams = @{ 
                diskSpdDownloadUrl = $diskSpdDownloadUrl
	            testParams = $testParams
	            testName = $testName
	            storageAccountKey = $storageKey
	            storageContainerName = $resultsContainerName
	            storageAccountName = $resultsStorageAccountName
				storageUrlDomain = $storageUrlDomain
				uploadUrlWithSas = $uploadSasToken + ''
            }
			
            # above we published the DSC to the root of the container
            Add-content $log "`ndeploying dsc extension to $vmName at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), time elapsed = $($sw.Elapsed.ToString())"
            Add-content $log "DiskSpd Params = $testParams, "

            # Install DSC Extension to run custom DSC resource:
            $dscResult = Set-AzVMDscExtension -Name Microsoft.Powershell.DSC -ArchiveBlobName 'DiskPrepTest.ps1.zip' `
            -ArchiveStorageAccountName $resultsStorageAccountName -ArchiveContainerName "$artifactsContainerName" `
            -ArchiveResourceGroupName $resultsStorageAccountRg -ResourceGroupName $resourceGroup -Version 2.83 -VMName $vmName `
            -ConfigurationArgument $dscConfigParams -ConfigurationName DiskPrepAndTest -ErrorVariable dscErrorOutput -OutVariable dscOutput -Verbose -AutoUpdate
                    
            if($dscErrorOutput){
                Add-content $log "dsc error, result: $dscErrorOutput"
            }
            if($dscOutput){
                Add-content $log "dsc successful, result: $dscOutput"
            }
                    
            Add-content $log "waiting for blob,$($sw.Elapsed.ToString())"

            # Required for storage account context
            $resultsStorage = Get-AzStorageAccount -ResourceGroupName $resultsStorageAccountRg -Name $resultsStorageAccountName

            $c = 6 
            Do{
                Get-AzStorageBlob -Blob "perf-trace-$testName-$vmName.blg" -Container $resultsContainerName `
                -Context $resultsStorage.Context -ErrorAction SilentlyContinue -ErrorVariable blgNotPresent
            
                Get-AzStorageBlob -Blob "perf-trace-$testName-$vmName.txt" -Container $resultsContainerName `
                -Context $resultsStorage.Context -ErrorAction SilentlyContinue -ErrorVariable txtNotPresent

                if($blgNotPresent)
                {
                    Add-content $log "checking for PerfMon blg blob"
                    Start-Sleep -Seconds 5
                } else {
                    Add-content $log "PerfMon blg blob found"
                }
                if($txtNotPresent)
                {
                    Add-content $log "checking for DiskSpd txt file blob"
                    Start-Sleep -Seconds 5
                } else {
                    Add-content $log "DiskSpd txt file blob found"
                }
            $c--
            } 
            Until([string]::IsNullOrEmpty($txtNotPresent) -or $c -le 0)

            if(-not $dontDeleteResourceGroupOnComplete){
                Add-content $log "starting deletion of resource group $resourceGroup,$($sw.Elapsed.ToString())"
                Remove-AzResourceGroup -Name $resourceGroup -Force
            }

        }

		Add-content $log "done,$($sw.Elapsed.ToString()),$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
		$sw.Stop()

    } -ArgumentList $params

    Write-Host "pausing for $pauseBetweenVmCreateInSeconds seconds`n"
    Start-Sleep -Seconds $pauseBetweenVmCreateInSeconds
}

Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $totalVmCount x ARM VM Fleet Jobs created...." -ForegroundColor Green

# Remove write progress bar, as all VMs have been created.
Write-Progress -Completed

Write-Host "`nInfo: Check the status of ARM VM Fleet jobs by reviewing VM log files in folder: $($logfilefolder)"
Write-Host "Info: Check the User Portal for VMs CPU metrics."
Write-Host "Info: For high-level performance statistics, check: Admin Portal --> Resource Providers --> Storage --> Volume Metrics --> Object Store"

Write-Host "`nWaiting for ARM VM Fleet PowerShell Jobs to complete....`n`nThis will take some time depending on the DiskSpd -d (test duratoin) parameter used.`n" -ForegroundColor Yellow

# PowerShell jobs hold the status and individual log files are created in $logfilefolder, which defaults to "C:\ARM-VMFleet-Logs\", per VM.
Get-Job | Wait-Job | Receive-Job
