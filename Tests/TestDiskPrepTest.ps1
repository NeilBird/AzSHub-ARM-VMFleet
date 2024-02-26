#
# TestDiskPrepTest.ps1
#

# get credential
#$creds = Get-Credential deployment


$configData =@{
    AllNodes = @(
        @{
            NodeName = "localhost";
			RebootNodeIfNeeded = $true;
			ActionAfterReboot = "ContinueConfiguration";
         }
    );

}

$params = @{
	diskSpdDownloadUrl = "https://github.com/microsoft/diskspd/releases/download/v2.1/DiskSpd.ZIP"
	testParams = '-c200M -b8K -t2 -o20 -d30'
	testName = 'iotest1'
	storageAccountKey = ''
	storageContainerName = 'stacktestresults'
	storageAccountName = 'testharness'
	uploadUrlWithSas = ''
}


DiskPrepAndTest @params -Verbose

Start-DscConfiguration -ComputerName localhost -Path .\DiskPrepAndTest -Verbose -Wait -Force