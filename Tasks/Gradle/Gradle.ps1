param(
    [string]$wrapperScript,   # Path to gradle wrapper. 
    [string]$cwd,             # Optional - Root directory of gradle project. Defaults to folder of gradle wrapper.
    [string]$options,         # Gradle options
    [string]$tasks,           # Gradle tasks
    [string]$jdkVersion,      # JDK version
    [string]$jdkArchitecture  # JDK arch
)

Write-Verbose "Entering script Gradle.ps1"
Write-Verbose "wrapperScript = $wrapperScript"
Write-Verbose "options = $options"
Write-Verbose "tasks = $tasks"

# Import the Task.Common dll that has all the cmdlets we need for Build
import-module "Microsoft.TeamFoundation.DistributedTask.Task.Common"

# Verify wrapperScript is set and is not a container
if(!$wrapperScript -or !(Test-Path -Path $wrapperScript -PathType Leaf)) 
{
    throw (Get-LocalizedString -Key "Please specify the Gradle wrapper script.")
}

# Find working directory. cwd is optional, we use directory of wrapper as working directory if not set.
if(!$cwd)
{
    $wrapperScriptItem = Get-Item -Path $wrapperScript
    $cwd = $wrapperScriptItem.Directory.FullName
}

Write-Verbose "Setting working directory to $cwd"
Push-Location $cwd

if($jdkVersion -and $jdkVersion -ne "default")
{
    $jdkPath = Get-JavaDevelopmentKitPath -Version $jdkVersion -Arch $jdkArchitecture
    if (!$jdkPath) 
    {
        throw (Get-LocalizedString -Key "Could not find JDK {0} {1}, please make sure the selected JDK is installed properly" -ArgumentList $jdkVersion, $jdkArchitecture)
    }

    Write-Verbose "Setting JAVA_HOME to $jdkPath"
    $env:JAVA_HOME = $jdkPath
    Write-Verbose "JAVA_HOME set to $env:JAVA_HOME"
}

$arguments = "$options $tasks"
Write-Verbose "Invoking Gradle wrapper $wrapperScript $arguments"
Invoke-BatchScript -Path $wrapperScript -Arguments $arguments

Pop-Location
Write-Verbose "Leaving script Gradle.ps1"
