$PSVersion = $PSVersionTable.PSVersion.Major
$ModuleName = $ENV:BHProjectName
$ModulePath = Join-Path $ENV:BHProjectPath $ModuleName

# Verbose output for non-master builds on appveyor
# Handy for troubleshooting.
# Splat @Verbose against commands as needed (here or in pester tests)
$Verbose = @{}
if($ENV:BHBranchName -notlike "master" -or $env:BHCommitMessage -match "!verbose") {
    $Verbose.add("Verbose", $True)
}

Import-Module $ModulePath -Force

Describe "IBMIM Sub-Module PS$PSVersion" {
    Context 'Strict mode' {

        Set-StrictMode -Version latest

        It 'Should load' {
            $Module = Get-Module $ModuleName
            $Module.Name | Should be $ModuleName
            $Commands = $Module.ExportedCommands.Keys
            $Commands -contains 'ConvertTo-HashedPassword' | Should Be $True
            $Commands -contains 'Get-IBMInstallationManagerHome' | Should Be $True
            $Commands -contains 'Get-IBMInstallationManagerTempDir' | Should Be $True
            $Commands -contains 'Get-IBMInstallationManagerVersion' | Should Be $True
            $Commands -contains 'Get-IBMTempDir' | Should Be $True
            $Commands -contains 'Install-IBMInstallationManager' | Should Be $True
            $Commands -contains 'Install-IBMProduct' | Should Be $True
            $Commands -contains 'Install-IBMProductViaCmdLine' | Should Be $True
            $Commands -contains 'Install-IBMProductViaResponseFile' | Should Be $True
            $Commands -contains 'New-IBMInstallationManagerResponseFile' | Should Be $True
            $Commands -contains 'Set-IBMInstallationManagerTempDir' | Should Be $True
            $Commands -contains 'Update-IBMInstallationManager' | Should Be $True
        }
    }
}

<#Describe "ConvertTo-HashedPassword PS$PSVersion" {
    Context "When a good password is provided" {
        Mock -ModuleName $ModuleName Get-IBMInstallationManagerHome {
            $iimcPath = Join-Path -Path $env:TEMP -ChildPath "eclipse"
            New-Item -ItemType Directory -Force -Path $iimcPath | Out-Null
            New-Item -ItemType File -Force -Path "$iimcPath\IBMIMc.exe" | Out-Null
            Return $env:TEMP
        }
        Mock Invoke-ProcessHelper {
            Return @{
                StdOut = "HASHED"
                ExitCode = 0
            }
        }
        It 'Should be able to generate a hashed password' {
            $cred = New-Object System.Management.Automation.PSCredential("testuser", "Passw0rd" | ConvertTo-SecureString -asPlainText -Force)
            $x = ConvertTo-HashedPassword -UserCredential $cred -Verbose
            Assert-MockCalled Invoke-ProcessHelper
            Assert-MockCalled Get-IBMInstallationManagerHome
            Write-Output $x
            $x -eq "HASHED" | Should Be $True
        }
    }
}#>