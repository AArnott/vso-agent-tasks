Write-Verbose "Starting SonarQube PostBuild Step"

import-module "Microsoft.TeamFoundation.DistributedTask.Task.Common"
. ./SonarQubeHelper.ps1

InvokeMsBuildRunnerPostTest
UploadSummaryMdReport

