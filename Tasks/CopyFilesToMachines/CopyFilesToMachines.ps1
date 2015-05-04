param (
    [string]$environmentName,
    [string]$machineNames, 
    [string]$sourcePath,
    [string]$targetPath,
    [string]$cleanTargetBeforeCopy,
    [string]$deployFilesInParallel
    )

Write-Verbose "Entering script DeployFilesToMachines.ps1" -Verbose
Write-Verbose "environmentName = $environmentName" -Verbose
Write-Verbose "machineNames = $machineNames" -Verbose
Write-Verbose "sourcePath = $sourcePath" -Verbose
Write-Verbose "targetPath = $targetPath" -Verbose
Write-Verbose "deployFilesInParallel = $deployFilesInParallel" -Verbose
Write-Verbose "cleanTargetBeforeCopy = $cleanTargetBeforeCopy" -Verbose

. ./CopyJob.ps1
. ./CopyFilesHelper.ps1

import-module "Microsoft.TeamFoundation.DistributedTask.Task.DevTestLabs"

	# Default + constants #
$defaultWinRMPort = '5985'
$defaultSkipCACheckOption = '-SkipCACheck'
$defaultHttpProtocolOption = '-UseHttp'
$resourceFQDNKeyName = 'Microsoft-Vslabs-MG-Resource-FQDN'
$resourceWinRMHttpPortKeyName = 'WinRM_HttpPort'
$resourceWinRMHttpsPortKeyName = 'WinRM_HttpsPort'
$envOperationStatus = 'Passed'

function Get-ResourceCredentials
{
	param([object]$resource)
		
	$machineUserName = $resource.Username
	Write-Verbose "`t`t Resource Username - $machineUserName" -Verbose
	$machinePassword = $resource.Password

	$credential = New-Object 'System.Net.NetworkCredential' -ArgumentList $machineUserName, $machinePassword
	
	return $credential
}

function Get-ResourceConnectionDetails
{
    param([string]$resourceName,
	[REF]$resourceProperties
	)
	
	$resourceProperties.value.httpProtocolOption = ''
	$resourceProperties.value.skipCACheckOption = $defaultSkipCACheckOption
	
	$winrmPort = Get-EnvironmentProperty -EnvironmentName $environmentName -Key $resourceWinRMHttpsPortKeyName -Connection $connection -ResourceName $resourceName -ErrorAction Stop
		
	if([string]::IsNullOrEmpty($winrmPort))
	{
		$winrmPort = Get-EnvironmentProperty -EnvironmentName $environmentName -Key $resourceWinRMHttpPortKeyName -Connection $connection -ResourceName $resourceName -ErrorAction Stop
		if([string]::IsNullOrEmpty($winrmPort))
		{
			Write-Verbose "`t`t Resource $resourceName does not have any winrm port defined , use the default - $defaultWinRMPort" -Verbose
			$winrmPort = $defaultWinrmPort
		}
		else
		{
			Write-Verbose "`t`t Resource $resourceName has winrm port defined as - $winrmPort" -Verbose
		}

		$resourceProperties.value.httpProtocolOption = $defaultHttpProtocolOption
	}
	else
	{
		# Do not use 'SkipCACheck' option in case of winrm https port
		$resourceProperties.value.skipCACheckOption = ''
		Write-Verbose "`t`t Resource $resourceName has winrm https port $winrmPort defined , CA option will be used to expand the target path if it is provided as environment variable " -Verbose
	}
	
	$resourceProperties.value.winrmPort = $winrmPort

}

function Get-ResourcesProperties
{
    param([object]$resources)

	$resourcesProperties = @()
	
	foreach ($resource in $resources)
    {
		[hashtable]$resourceProperties = @{} 
		
		$resourceName = $resource.Name
		Write-Verbose "Get Resource properties for $resourceName" -Verbose		
		
		$fqdn = Get-EnvironmentProperty -EnvironmentName $environmentName -Key $resourceFQDNKeyName -Connection $connection -ResourceName $resourceName -ErrorAction Stop
		
		Write-Verbose "`t`t Resource fqdn - $fqdn" -Verbose	
		
		$resourceProperties.fqdn = $fqdn

		# Get other connection details for resource like - wirmport , http protocol , skipCACheckOption
		
		$resourceOtherConnectionDetails = Get-ResourceConnectionDetails -resourceName $resourceName
		
		$resourceProperties.winrmPort = $resourceOtherConnectionDetails.winrmPort
		
		$resourceProperties.skipCACheckOption = $resourceOtherConnectionDetails.skipCACheckOption
		
		$resourceProperties.httpProtocolOption = $resourceOtherConnectionDetails.httpProtocolOption
		
		$resourceProperties.credential = Get-ResourceCredentials -resource $resource
		
		$resourcesProperties += $resourceProperties
	}
	 return $resourcesProperties
}

$connection = Get-VssConnection -TaskContext $distributedTaskContext

$resources = Get-EnvironmentResources -EnvironmentName $environmentName -ResourceFilter $machineNames -Connection $connection -ErrorAction Stop

$envOperationId = Invoke-EnvironmentOperation -EnvironmentName $environmentName -OperationName "Copy Files" -Connection $connection -ErrorAction Stop

Write-Verbose "envOperationId = $envOperationId" -Verbose

$resourcesProperties = Get-ResourcesProperties -resources $resources

if($deployFilesInParallel -eq "false" -or  ( $resources.Count -eq 1 ) )
{
    foreach ($resourceProperty in $resourcesProperties)
    {    	
        $machine = $resourceProperty.fqdn
		
        Write-Output "Copy Started for - $machine"

		$resOperationId = Invoke-ResourceOperation -EnvironmentName $environmentName -ResourceName $machine -EnvironmentOperationId $envOperationId -Connection $connection -ErrorAction Stop
		Write-Verbose "ResourceOperationId = $resOperationId" -Verbose
		
        $copyResponse = Invoke-Command -ScriptBlock $CopyJob -ArgumentList $machine, $sourcePath, $targetPath, $resourceProperty.credential, $cleanTargetBeforeCopy, $resourceProperty.winrmPort, $resourceProperty.httpProtocolOption, $resourceProperty.skipCACheckOption
       
        $status = $copyResponse.Status
        Output-ResponseLogs -operationName "copy" -fqdn $machine -deploymentResponse $copyResponse
        Write-Output "Copy Status for machine $machine : $status"
		
		Write-Verbose "Do complete ResourceOperation for  - $machine" -Verbose
		
		DoComplete-ResourceOperation -environmentName $environmentName -envOperationId $envOperationId -resOperationId $resOperationId -connection $connection -deploymentResponse $copyResponse

        if($status -ne "Passed")
        {
            Complete-EnvironmentOperation -EnvironmentName $environmentName -EnvironmentOperationId $envOperationId -Status "Failed" -Connection $connection -ErrorAction Stop

            throw $copyResponse.Error
        }
    } 
}
else
{
    [hashtable]$Jobs = @{} 

    foreach ($resourceProperty in $resourcesProperties)
    {    	
        $machine = $resourceProperty.fqdn
		
        Write-Output "Copy Started for - $machine"
		
		[hashtable]$resourceProperties = @{} 
		
		$resOperationId = Invoke-ResourceOperation -EnvironmentName $environmentName -ResourceName $machine -EnvironmentOperationId $envOperationId -Connection $connection -ErrorAction Stop
		
		Write-Verbose "ResourceOperationId = $resOperationId" -Verbose
		
		$resourceProperties.machineName = $machine
		$resourceProperties.resOperationId = $resOperationId

        $job = Start-Job -ScriptBlock $CopyJob -ArgumentList $machine, $sourcePath, $targetPath, $resourceProperty.credential, $cleanTargetBeforeCopy, $resourceProperty.winrmPort, $resourceProperty.httpProtocolOption, $resourceProperty.skipCACheckOption

        $Jobs.Add($job.Id, $resourceProperties)
		
    }

    While (Get-Job)
    {
         Start-Sleep 10 
         foreach($job in Get-Job)
         {
             if($job.State -ne "Running")
             {
                 $output = Receive-Job -Id $job.Id
                 Remove-Job $Job
                 $status = $output.Status

                 if($status -ne "Passed")
                 {
                     $envOperationStatus = "Failed"
                 }
				 
				 $machineName = $Jobs.Item($job.Id).machineName
				 $resOperationId = $Jobs.Item($job.Id).resOperationId

                 Output-ResponseLogs -operationName "copy" -fqdn $machineName -deploymentResponse $output
				 
                 Write-Output "Copy Status for machine $machineName : $status"
				 
				 DoComplete-ResourceOperation -environmentName $environmentName -envOperationId $envOperationId -resOperationId $resOperationId -connection $connection -deploymentResponse $output
              } 
        }
    }
}

Complete-EnvironmentOperation -EnvironmentName $environmentName -EnvironmentOperationId $envOperationId -Status $envOperationStatus -Connection $connection -ErrorAction Stop

if($envOperationStatus -ne "Passed")
{
    throw "copy to one or more machine failed."
}

