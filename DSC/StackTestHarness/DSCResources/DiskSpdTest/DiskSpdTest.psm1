function Get-TargetResource
{
	[CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param
    (
        [ValidateSet("Present", "Absent")]
        [string]$Ensure = "Present",

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$PhysicalPathToDiskSpd,

        [Parameter(Mandatory)]
        [string]$DiskSpdParameters,
		
        [Parameter(Mandatory)]
		[String]$TestName,
		
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ResultsOutputDirectory,
		
		[string]$StorageAccountName,
		[string]$StorageAccountKey,
		[string]$StorageContainerName,
		[String]$StorageUrlDomain,

		[String]$UploadUrlWithSas,

        [string[]]$PerformanceCounters = @('\PhysicalDisk(*)\*', '\Processor Information(*)\*', '\Memory(*)\*', '\Network Interface(*)\*')

    )

	$getTargetResourceResult =  @{}

    $getTargetResourceResult;
}

function Set-TargetResource
{
    [CmdletBinding()]
    param
    (
        [ValidateSet("Present", "Absent")]
        [string]$Ensure = "Present",

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$PhysicalPathToDiskSpd,

        [Parameter(Mandatory)]
        [string]$DiskSpdParameters,
		
        [Parameter(Mandatory)]
		[String]$TestName,
		
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ResultsOutputDirectory,
		
		[string]$StorageAccountName,
		[string]$StorageAccountKey,
		[string]$StorageContainerName,
		[String]$StorageUrlDomain,
		[String]$UploadUrlWithSas,

        [string[]]$PerformanceCounters = @('\PhysicalDisk(*)\*', '\Processor Information(*)\*', '\Memory(*)\*', '\Network Interface(*)\*')
    )
	$n = "perf-trace-$TestName-$env:COMPUTERNAME"
	$resultsPath = [io.path]::combine($ResultsOutputDirectory, $n + ".blg")
	$resultsExist = [System.IO.File]::Exists($resultsPath)

    <# If Ensure is set to "Present" and the results file does not exist, then run test using the specified parameter values #>
	if(-not $resultsExist -and $Ensure -eq "Present"){
		
		$iopsTestFilePath = [io.path]::combine($ResultsOutputDirectory, $TestName + ".dat")
		$testHarnessfile = [System.IO.FileInfo][io.path]::combine($ResultsOutputDirectory, $n + ".txt")
		$diskSpdPath = [io.path]::combine($PhysicalPathToDiskSpd, "diskspd.exe")


		Add-Content -Path $testHarnessfile -Value "PhysicalPathToDiskSpd:$PhysicalPathToDiskSpd"
		Add-Content -Path $testHarnessfile -Value "DiskSpdParams:$DiskSpdParameters"
		Add-Content -Path $testHarnessfile -Value "TestName:$TestName"
		Add-Content -Path $testHarnessfile -Value "PerfCounters:$([system.String]::Join(",",$PerformanceCounters))"

		Write-Verbose "Running test $TestName with params $DiskSpdParameters"

		start-logman $env:COMPUTERNAME $TestName $PerformanceCounters

		# run the diskspd test and output to a file
		$cmd = "$diskSpdPath $DiskSpdParameters $iopsTestFilePath"
		Invoke-Expression $cmd -ErrorAction SilentlyContinue -ErrorVariable diskSpdError -OutVariable diskspdOut -WarningAction SilentlyContinue *>&1

		Add-Content -Path $testHarnessfile -Encoding UTF8 -Value "DiskSpd Results:`n$diskspdOut"

		# upload iops test file to test the network
		#$endpoint = "$($UploadUrlWithSas.Split('?')[0])/$("$TestName.dat")?$($UploadUrlWithSas.Split('?')[1])"
		#Write-Verbose "Uploading test iops file $iopsTestFilePath to $UploadUrlWithSas"
		#Write-Verbose "$endpoint"
		#$headers = @{
			#"x-ms-blob-type"="BlockBlob"
            #"x-ms-version"='2016-05-31'
			#"Content-Length"=(Get-Item $iopsTestFilePath).length
		#}
		
		#$response = Invoke-RestMethod -method PUT -InFile $iopsTestFilePath `
					#-Uri $endpoint `
                    #-Headers $headers -ErrorVariable uploadError -Verbose
		
		#if($uploadError){
			#Add-Content -Path $testHarnessfile -Value "UploadError:$uploadError"
		#}
		#else{
			# download the file we just uploaded to continue test of the network
        
		#	Write-Verbose "Downloading file $endpoint"
			#$wc = New-Object System.Net.WebClient
			#$wc.Headers["User-Agent"] = "Mozilla/4.0 (compatible; MSIE 6.0; Windows NT 5.2; .NET CLR 1.0.3705;)"
			#$wc.DownloadFile($endpoint,([io.path]::combine($ResultsOutputDirectory, "$TestName-download.dat")))
		#}

		# stops the performance counters and copies output to $resultsPath
		stop-logman $env:COMPUTERNAME $TestName $ResultsOutputDirectory
		
		upload-to-blob-storage $storageUrlDomain $storageAccountName $storageAccountKey $UploadUrlWithSas $storageContainerName $resultsPath
		upload-to-blob-storage $storageUrlDomain $storageAccountName $storageAccountKey $UploadUrlWithSas $storageContainerName $testHarnessfile
		
		Write-Verbose "Uploaded results to storage. Done."
	}

}



function Test-TargetResource
{
	[CmdletBinding()]
    [OutputType([System.Boolean])]
	param
    (
        [ValidateSet("Present", "Absent")]
        [string]$Ensure = "Present",

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$PhysicalPathToDiskSpd,

        [Parameter(Mandatory)]
        [string]$DiskSpdParameters,
		
        [Parameter(Mandatory)]
		[String]$TestName,
		
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ResultsOutputDirectory,
		
		[string]$StorageAccountName,
		[string]$StorageAccountKey,
		[string]$StorageContainerName,
		[String]$StorageUrlDomain,
		[String]$UploadUrlWithSas,

        [string[]]$PerformanceCounters = @('\PhysicalDisk(*)\*', '\Processor Information(*)\*', '\Memory(*)\*', '\Network Interface(*)\*')
    )

	#Write-Verbose "Use this cmdlet to deliver information about command processing."

	#Write-Debug "Use this cmdlet to write debug information while troubleshooting."


	#Include logic to
	$resultsPath = [io.path]::combine($ResultsOutputDirectory, $env:COMPUTERNAME + "-" + $TestName + ".blg")
	$resultsExist = [System.IO.File]::Exists($resultsPath)
	#Add logic to test whether the website is present and its status matches the supplied parameter values. If it does, return true. If it does not, return false.
	$resultsExist
}




function upload-to-blob-storage(
		[String] $storageUrlDomain, # for Azure this would be blob.core.windows.net but will differ for Stack
		[string] $StorageAccount, # the name of the storage account
		[string] $Key,  # storage account key
		[string] $UploadUrlWithSas,
		[string] $containerName,
		[string] $file
	)
{
	$fileobject = get-item $file
	$fileLength=$fileobject.length
	$fileName=$fileobject.Name
			# upload iops test file to test the network
			$endpoint = "$($UploadUrlWithSas.Split('?')[0])/$("$fileName")?$($UploadUrlWithSas.Split('?')[1])"
			Write-Verbose "Uploading results to storage...file length is $fileLength"
			Write-Verbose "Uploading $filename to $UploadUrlWithSas"
			Write-Verbose "Endpoint: $endpoint"
			$headers = @{
				"x-ms-blob-type"="BlockBlob"
				"x-ms-version"='2016-05-31'
				"Content-Length"=$fileLength
			}
			
			$response = Invoke-RestMethod -method PUT -InFile $fileobject.FullName `
						-Uri $endpoint `
						-Headers $headers -ErrorVariable uploadError -Verbose
			if($uploadError){
				Add-Content -Path $testHarnessfile -Value "UploadError:$uploadError"
			}
			else{
				Write-Verbose "Uploaded $file to $endpoint successfully"
				Add-Content -Path $testHarnessfile -Value "Uploaded file Successful: $response"
			}
}


function start-logman(
    [string] $computer,
    [string] $name,
    [string[]] $counters
    )
{
    $f = "c:\perf-trace-$name-$computer.blg"

    $null = logman create counter "perf-trace-$name" -o $f -f bin -si 1 --v -c $counters -s $computer
    $null = logman start "perf-trace-$name" -s $computer
    write-host "performance counters on: $computer"
}

function stop-logman(
    [string] $computer,
    [string] $name,
    [string] $path
    )
{
    $f = "c:\perf-trace-$name-$computer.blg"
    
    $null = logman stop "perf-trace-$name" -s $computer
    $null = logman delete "perf-trace-$name" -s $computer
    xcopy /j $f $path
    del -force $f
    write-host "performance counters off: $computer"
}


Export-ModuleMember -Function *-TargetResource