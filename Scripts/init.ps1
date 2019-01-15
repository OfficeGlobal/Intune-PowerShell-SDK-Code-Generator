# Get init script directory
$env:PowerShellSDKRepoRoot = Split-Path (Split-Path $script:MyInvocation.MyCommand.Path -Parent) -Parent

# Environment variables
$env:buildConfiguration = "Release"
$global:allowedDotnetFrameworkVersions = @('net471', 'netstandard2.0')
$env:dotnetFrameworkVersion = ($global:allowedDotnetFrameworkVersions)[0] # use "netstandard2.0" for cross-platform build, or "net471" for a Windows build
$env:repoRootSlnFile = "$($env:PowerShellSDKRepoRoot)\PowerShellGraphSDKGenerator.sln"
$env:writerDir = "$($env:PowerShellSDKRepoRoot)\src\GraphODataPowerShellWriter"
$env:writerBuildDir = "$($env:writerDir)\bin\$($env:buildConfiguration)"
$env:generatedDir = "$($env:writerBuildDir)\output"
$env:sdkDir = "$($env:generatedDir)\bin\$($env:buildConfiguration)\$($env:dotnetFrameworkVersion)"
$env:testDir = "$($env:PowerShellSDKRepoRoot)\Tests"
$env:moduleName = 'Microsoft.Graph.Intune'
$env:moduleExtension = 'psd1'
$env:sdkSubmoduleSrc = "$($env:PowerShellSDKRepoRoot)\submodules\Intune-PowerShell-SDK"
$env:nugetExe = "nuget.exe"
$env:adminUPN = "admin@roramutesta063.onmicrosoft.com"

# Remember the settings that will change when launching a child PowerShell context
$env:standardWindowTitle = (Get-Host).UI.RawUI.WindowTitle
$env:standardForegroundColor = (Get-Host).UI.RawUI.ForegroundColor
$env:standardBackgroundColor = (Get-Host).UI.RawUI.BackgroundColor

# Scripts
$env:msbuildInstallScript = "$($env:PowerShellSDKRepoRoot)\Scripts\msbuild-install.ps1"
$env:dotnetInstallScript = "$($env:PowerShellSDKRepoRoot)\Scripts\dotnet-install.ps1"
$env:buildScriptPortable = "$($env:PowerShellSDKRepoRoot)\Scripts\build-portable.ps1"
$env:buildScriptFull = "$($env:PowerShellSDKRepoRoot)\Scripts\build-full.ps1"
$env:runScript = "$($env:PowerShellSDKRepoRoot)\Scripts\run.ps1"
$env:testScript = "$($env:PowerShellSDKRepoRoot)\Scripts\test.ps1"
$env:ListCmdletsScript = "$($env:PowerShellSDKRepoRoot)\src\PowerShellGraphSDK\Scripts\ListCmdlets.ps1"

###############
## Functions ##
###############

function global:BuildWriter {
    Write-Host "Building the writer..." -f Cyan
    Invoke-Expression "$env:buildScriptFull -WorkingDirectory '$env:writerDir' -Verbosity 'quiet'"
    Write-Host "Finished building the writer" -f Cyan
    Write-Host
}

function global:RunWriter {
    param (
        [string]$GraphSchema
    )

    Write-Host "Running the writer (i.e. generating the cmdlets)..." -f Cyan
    Invoke-Expression "$env:buildScriptFull -WorkingDirectory '$env:writerDir' -BuildTargets 'Run' -GraphSchema '$GraphSchema'"
    Write-Host "Finished running the writer" -f Cyan
    Write-Host
}

function global:BuildSDK {
    param(
        [string]$WorkingDirectory
    )

    # Build the SDK
    Write-Host "Building the SDK (i.e. building the generated cmdlets)..." -f Cyan
    Invoke-Expression "$env:buildScriptPortable -WorkingDirectory '$WorkingDirectory' -Verbosity 'quiet'"
    Write-Host "Finished building the SDK" -f Cyan
    Write-Host
}

function global:RunSDK {
    [alias("run")]
    param(
        [string]$TargetFramework = $env:dotnetFrameworkVersion
    )

    if (-Not $global:allowedDotnetFrameworkVersions.Contains($TargetFramework)) {
        throw "The target framework must be set to one of the following: $([string]::Join(', ', $global:allowedDotnetFrameworkVersions))"
    }

    $SdkDirectory = $env:sdkDir
    if ($TargetFramework -ne $env:dotnetFrameworkVersion)
    {
        $SdkDirectory = $SdkDirectory.Replace($env:dotnetFrameworkVersion, $TargetFramework)
    }

    Write-Host "Running the SDK (importing '$env:moduleName' and running 'Connect-MSGraph')..." -f Cyan
    Invoke-Expression "$env:runScript -SdkDirectory $SdkDirectory"
}

function global:TestSDK {
    [alias("test")]
    param(
        [string]$TargetFramework = $env:dotnetFrameworkVersion
    )

    if (-Not $global:allowedDotnetFrameworkVersions.Contains($TargetFramework)) {
        throw "The target framework must be set to one of the following: $([string]::Join(', ', $global:allowedDotnetFrameworkVersions))"
    }

    $SdkDirectory = $env:sdkDir
    if ($TargetFramework -ne $env:dotnetFrameworkVersion)
    {
        $SdkDirectory = $SdkDirectory.Replace($env:dotnetFrameworkVersion, $TargetFramework)
    }

    Invoke-Expression "$env:testScript -SdkDirectory $SdkDirectory"
}

function global:GenerateSDK {
    [alias("build")]
    param (
        [string]$GraphSchema
    )

    global:BuildWriter
    global:RunWriter -GraphSchema $GraphSchema
    global:BuildSDK -WorkingDirectory "$env:generatedDir"
    Invoke-Expression "$env:ListCmdletsScript -OutputDirectory $env:sdkDir -IsFullOutput"
}

function global:GenerateAndRunSDK {
    param (
        [string]$GraphSchema
    )

    global:GenerateSDK -GraphSchema $GraphSchema
    global:RunSDK
}

function global:ReleaseSDK {
    [alias("release")]
    param()

    if (-Not (Test-Path $env:generatedDir)) {
        throw "An SDK build was not found at '$env:generatedDir' - run 'build' before running 'release'"
    }

    Write-Host "Copying generated SDK" -f Cyan
    Remove-Item "$env:sdkSubmoduleSrc" -Recurse -ErrorAction SilentlyContinue
    New-Item "$env:sdkSubmoduleSrc" -ItemType directory -ErrorAction SilentlyContinue | Out-Null
    Copy-Item "$env:generatedDir\*" -Destination "$env:sdkSubmoduleSrc" -Recurse -Force -Container

    Write-Host "REMINDER: Make sure to correctly commit this change to the 'Intune-PowerShell-SDK' git submodule" -f Yellow
}

function global:InstallDotnetCore {
    Invoke-Expression "$env:dotnetInstallScript"
}

function global:InstallDotnetFramework {
    Invoke-Expression "$env:msbuildInstallScript"
}

##########
## Init ##
##########

# Try to download the "dotnet" install script if it doesn't exist
if (-Not (Test-Path $env:dotnetInstallScript -PathType Leaf)) {
    try {
        Invoke-WebRequest 'https://dot.net/v1/dotnet-install.ps1' -OutFile $env:dotnetInstallScript
    } catch {
        Write-Warning "Failed to download 'dotnet' command installer - builds will fail if you do not have 'dotnet' installed"
    }
}

# Try to download the "nuget" executable if it doesn't exist
if (-Not (Test-Path $env:nugetExe -PathType Leaf)) {
    try {
        Invoke-WebRequest 'https://dist.nuget.org/win-x86-commandline/latest/nuget.exe' -OutFile $env:nugetExe
    } catch {
        Write-Warning "Failed to download 'nuget' executable - builds may fail if you do not have 'nuget' installed"
    }
}

# Restore NuGet packages
dotnet restore --verbosity quiet
Invoke-Expression "./$env:nugetExe restore -Verbosity Quiet"

# Show the available functions
Write-Host "Initialized repository." -f Green
Write-Host "Available commands:" -f Yellow
Write-Host "    GenerateAndRunSDK             " -NoNewline -f Cyan; Write-Host ' | ' -NoNewline -f Gray; Write-Host "Executes the commands 'GenerateSDK' and 'RunSDK' (in that order)" -f DarkCyan
Write-Host "    GenerateSDK (or 'build')      " -NoNewline -f Cyan; Write-Host ' | ' -NoNewline -f Gray; Write-Host "Executes the commands 'BuildWriter', 'RunWriter' and 'BuildSDK' (in that order)" -f DarkCyan
Write-Host "    BuildWriter                   " -NoNewline -f Cyan; Write-Host ' | ' -NoNewline -f Gray; Write-Host "Builds the GraphODataPowerShellSDKWriter project" -f DarkCyan
Write-Host "    RunWriter                     " -NoNewline -f Cyan; Write-Host ' | ' -NoNewline -f Gray; Write-Host "Runs the GraphODataPowerShellSDKWriter project" -f DarkCyan
Write-Host "    BuildSDK                      " -NoNewline -f Cyan; Write-Host ' | ' -NoNewline -f Gray; Write-Host "Builds the generated PowerShellSDK project" -f DarkCyan
Write-Host "    RunSDK (or 'run')             " -NoNewline -f Cyan; Write-Host ' | ' -NoNewline -f Gray; Write-Host "Runs the generated PowerShellSDK project" -f DarkCyan
Write-Host "    TestSDK (or 'test')           " -NoNewline -f Cyan; Write-Host ' | ' -NoNewline -f Gray; Write-Host "Runs tests against the generated PowerShellSDK project" -f DarkCyan
Write-Host "    ReleaseSDK (or 'release')     " -NoNewline -f Cyan; Write-Host ' | ' -NoNewline -f Gray; Write-Host "Releases the generated SDK to https://github.com/Microsoft/Intune-PowerShell-SDK." -f DarkCyan
Write-Host
