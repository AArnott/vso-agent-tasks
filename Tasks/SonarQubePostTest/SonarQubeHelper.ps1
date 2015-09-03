function InvokeMsBuildRunnerPostTest
{
	$bootstrapperPath = GetBoostrapperPath
	$arguments = GetMsBuildRunnerPostTestArgs

	Write-Verbose -Verbose "Executing $bootstrapperPath with arguments $arguments"
	Invoke-BatchScript $bootstrapperPath -Arguments $arguments
}

function GetBoostrapperPath
{
	$bootstrapperPath = GetTaskContextVariable "bootstrapperPath" 

	if (!$bootstrapperPath -or ![System.IO.File]::Exists($bootstrapperPath))
	{
		throw "The SonarQube MsBuild Runner executable could not be found. Does your build definition include the SonarQube Pre-Build step?"
	}

	Write-Verbose -Verbose "bootstrapperPath: $bootstrapperPath"
	return $bootstrapperPath;
}

#
# Remarks: Normally all the settings are stored in a file on the build agent, but some well-known sensitive settings need to 
# be passed again as they cannot be stored in non-encrypted files
#
function GetMsBuildRunnerPostTestArgs()
{
	  $serverUsername = GetTaskContextVariable "serverUsername" 
	  $serverPassword = GetTaskContextVariable "serverPassword" 
	  $dbUsername = GetTaskContextVariable "dbUsername" 
	  $dbPassword = GetTaskContextVariable "dbPassword" 

	  $sb = New-Object -TypeName "System.Text.StringBuilder"; 
      [void]$sb.Append("end");

	
      if (![String]::IsNullOrWhiteSpace($serverUsername))
      {
          [void]$sb.Append(" /d:sonar.login=""$serverUsername""")
      }
	  
      if (![String]::IsNullOrWhiteSpace($serverPassword))
      {
          [void]$sb.Append(" /d:sonar.password=""$serverPassword""")
      }
	  
	   if (![String]::IsNullOrWhiteSpace($dbUsername))
      {
          [void]$sb.Append(" /d:sonar.jdbc.username=""$dbUsername""")
      }
	  
      if (![String]::IsNullOrWhiteSpace($dbPassword))
      {
          [void]$sb.Append(" /d:sonar.jdbc.password=""$dbPassword""")
      }

	return $sb.ToString();
}

function UploadSummaryMdReport
{
	#todo: do not print args to the console
	$agentBuildDirectory = GetTaskContextVariable "Agent.BuildDirectory" 
	if (!$agentBuildDirectory)
	{
		throw "Could not retrieve the Agent.BuildDirectory variable";
	}

	# Upload the summary markdown file
	$summaryMdPath = [System.IO.Path]::Combine($agentBuildDirectory, ".sonarqube", "out", "summary.md")
	Write-Verbose -Verbose "summaryMdPath = $summaryMdPath"

	if ([System.IO.File]::Exists($summaryMdPath))
	{
		Write-Verbose -Verbose "Uploading the summary.md file"
		Write-Host "##vso[build.uploadsummary]$summaryMdPath"
	}
	else
	{
		 Write-Warning "Could not find the summary report file $summaryMdPath"
	}
}


################# Helpers ######################


function GetTaskContextVariable()
{
	param([string][ValidateNotNullOrEmpty()]$varName)
	return Get-TaskVariable -Context $distributedTaskContext -Name $varName -Global $FALSE
}