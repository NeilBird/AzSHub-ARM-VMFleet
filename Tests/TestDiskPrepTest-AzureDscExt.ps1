$key = Read-Host "key"
$sas = Read-Host "url"
$location = Read-Host "location"


$paramHash = @{ 
    diskSpdDownloadUrl = "https://github.com/microsoft/diskspd/releases/download/v2.1/DiskSpd.ZIP"
	testParams = '-c200M -b8K -t2 -o40 -d30'
	testName = 'dsctest'
	storageAccountKey = $key + ''
	storageContainerName = 'stacktestresults'
	storageAccountName = 'testharness2'
	uploadUrlWithSas =  $sas + ''
}
 
# Create resource group
New-AzResourceGroup -Name TestHarness -Location $location

New-AzStorageAccount -ResourceGroupName TestHarness -Name testharness -Location $location -SkuName Standard_LRS -Kind Storage -Verbose

# publish the configuration with resources
Publish-AzVMDscConfiguration -ConfigurationPath .\DSC\DiskPrepTest.ps1 -ResourceGroupName "TestHarness" `
	-StorageAccountName "testharness2" -ContainerName "artifacts" -Force -Verbose

Set-AzVMDscExtension -Name Microsoft.Powershell.DSC -ArchiveBlobName DiskPrepTest.ps1.zip -ArchiveStorageAccountName testharness -ArchiveContainerName artifacts -ArchiveResourceGroupName TestHarness `
-ResourceGroupName STA-1 -Version 2.21 -VMName first1 -ConfigurationArgument $paramHash -ConfigurationName DiskPrepAndTest -Verbose