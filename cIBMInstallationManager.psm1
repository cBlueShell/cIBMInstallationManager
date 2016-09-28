# Import IBM Installation Manager Utils Module
Using Module BlueShellUtils
Import-Module $PSScriptRoot\IBMIM\IBMIM.psm1 -ErrorAction Stop

<#
   DSC resource to manage the installation of IBM Installation Manager.
   Key features: 
    - Install IBM Installation Manager for the first time
    - Update an existing installation
    - Can use media on the local drive as well as from a network share which may require specifying credentials
#>

[DscResource()]
class cIBMInstallationManager {
    [DscProperty(Key)]
    [String] $Version

    [DscProperty(Mandatory)]
    [Ensure] $Ensure
    
    [DscProperty()]
    [String] $InstallationDirectory = "C:\IBM\InstallationManager"

    [DscProperty()]
    [String] $SourcePath
    
    [DscProperty()]
    [System.Management.Automation.PSCredential] $SourcePathCredential
    
    [DscProperty()]
    [String] $TempDir

    <#
        Performs the installation or udpate of IBM Installation Manager.  It will only update an existing
        installation if the desired version is newer
    #>
    [void] Set () {
        try {
            if ($this.Ensure -eq [Ensure]::Present) {
                Write-Verbose -Message 'Starting installation of IBM Installation Manager'
                $currentIIMHome = Get-IBMInstallationManagerHome
                if ([string]::IsNullOrEmpty($currentIIMHome)) {
                    Install-IBMInstallationManager -iimHome $this.InstallationDirectory -iimMedia $this.SourcePath -iimMediaCredential $this.SourcePathCredential -TempDir $this.TempDir
                } else {
                    Write-Warning "IBM Installation Manager has already been installed, checking if needs to be updated"
                    $iimRsrc = $this.Get()
                    if ($iimRsrc.Version) {
                        # There's an IBM Installation Manager installed, we may need to update it
                        [System.Version] $currentVersion = New-Object -TypeName System.Version -ArgumentList $iimRsrc.Version
                        [System.Version] $newVersion = New-Object -TypeName System.Version -ArgumentList $this.Version
                        if ($newVersion.CompareTo($currentVersion) -gt 0) {
                            Update-IBMInstallationManager -iimHome $this.InstallationDirectory -iimMedia $this.SourcePath -Version $this.Version -iimMediaCredential $this.SourcePathCredential -TempDir $this.TempDir
                        } elseif ($newVersion.CompareTo($currentVersion) -lt 0) {
                            Write-Error "IBM Installation Manager already installed and its version ($currentVersion) is greater than the version specified ($newVersion)"
                        }
                    }
                }
                $cTempDir = Get-IBMInstallationManagerTempDir
                if ($this.TempDir -and ($this.TempDir -ne $cTempDir)) {
                    Set-IBMInstallationManagerTempDir ($this.TempDir)
                    $updatedTempDir = Get-IBMInstallationManagerTempDir
                    if (!($updatedTempDir -eq $this.TempDir)) {
                        Write-Error "Unable to update the IBM Installation Manager Temp Directory"
                    }
                }
            } else {
                Write-Verbose "Uninstalling IBM Installation Manager (Not Yet Implemented)"
            }
        } catch {
            Write-Error -ErrorRecord $_ -ErrorAction Stop
        }
    }

    <#
        Performs test to check if IBM Installation Manager is in the desired state, includes 
        validation of installation directory and version
    #>
    [bool] Test () {
        Write-Verbose "Checking for IBM Installation Manager installation"
        $iimConfiguredCorrectly = $false
        $iimRsrc = $this.Get()
        
        if (($iimRsrc.Ensure -eq $this.Ensure) -and ($iimRsrc.Ensure -eq [Ensure]::Present)) {
            if ($iimRsrc.Version -eq $this.Version) {
                if (((Get-Item($iimRsrc.InstallationDirectory)).Name -eq 
                    (Get-Item($this.InstallationDirectory)).Name) -and (
                    (Get-Item($iimRsrc.InstallationDirectory)).Parent.FullName -eq 
                    (Get-Item($this.InstallationDirectory)).Parent.FullName)) {
                    if (!($this.TempDir) -or ($iimRsrc.TempDir -eq $this.TempDir)) {
                        Write-Verbose "IBM Installation Manager is installed and configured correctly"
                        $iimConfiguredCorrectly = $true
                    }
                }
            }
        } elseif (($iimRsrc.Ensure -eq $this.Ensure) -and ($iimRsrc.Ensure -eq [Ensure]::Absent)) {
            $iimConfiguredCorrectly = $true
        }

        if (!($iimConfiguredCorrectly)) {
            Write-Verbose "IBM Installation Manager not configured correctly"
        }
        
        return $iimConfiguredCorrectly
    }

    <#
        Leverages the information stored in the registry to populate the properties of an existing
        installation of IBM Installation Manager
    #>
    [cIBMInstallationManager] Get () {
        $RetEnsure = [Ensure]::Absent
        $RetInsDir = $null
        $RetVersion = $null
        $RetTempDir = $null
        
        $iimHome = Get-IBMInstallationManagerHome

        if((Test-Path($this.InstallationDirectory)) -and ($iimHome) -and (Test-Path($iimHome))) {
            $iimSWTagFile = Join-Path -Path $this.InstallationDirectory -ChildPath "properties\version\*.swtag"
            if(Test-Path($iimSWTagFile)) {
                Write-Debug "IBM Installation Manager is Present"
                $RetEnsure = [Ensure]::Present
                $RetInsDir = $iimHome
                Write-Debug "IBM Installation Manager Directory: $RetInsDir"
                $RetVersion = Get-IBMInstallationManagerVersion
                Write-Debug "IBM Installation Manager Version: $RetVersion"
                $RetTempDir = Get-IBMInstallationManagerTempDir
            }
        } else {
            Write-Verbose "IBM Installation Manager is NOT Present"
        }

        $returnValue = @{
            InstallationDirectory = $RetInsDir
            Version = $RetVersion
            Ensure = $RetEnsure
            TempDir = $RetTempDir
        }

        return $returnValue
    }
}