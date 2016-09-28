#Requires -RunAsAdministrator
[cmdletbinding()]
param(
    [string[]] $Task = 'Default'
)

if (!(Get-PackageProvider -Name Nuget -ErrorAction SilentlyContinue)) {
    Install-PackageProvider -Name NuGet -Force
}

$modulesToInstall = @(
    'Pester',
    'Psake',
    'BuildHelpers',
    'PSDeploy',
    'PSScriptAnalyzer'
)

ForEach ($module in $modulesToInstall) {
    if (!(Get-Module -Name $module -ListAvailable)) {
        Install-Module -Name $module -Force -Scope CurrentUser
    }
}

Import-Module Psake, BuildHelpers

Set-BuildEnvironment

if (-not($env:APPVEYOR)) {
    $env:appveyor_build_version = '10.10.10'
    Write-Verbose "Not on AppVeyor, using fake version of $($env:appveyor_build_version)."
}

# Invoke PSake
Invoke-psake -buildFile "$PSScriptRoot\psake.ps1" -taskList $Task -parameters @{'build_version' = $env:appveyor_build_version} -Verbose:$VerbosePreference
exit ( [int]( -not $psake.build_success ) )