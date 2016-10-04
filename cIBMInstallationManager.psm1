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

# Ensure Enum - Used by most DSC Resources
enum Ensure {
    Absent
    Present
}

# Startup Type - Startup Options for Windows Services
enum StartupType {
    Automatic
    Manual
    Disabled
}

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
        $CurrentRsrc = [cIBMInstallationManager]::new()
        $CurrentRsrc.Ensure = [Ensure]::Absent
        $CurrentRsrc.InstallationDirectory = $null
        $CurrentRsrc.Version = $null
        $CurrentRsrc.TempDir = $null
        
        $iimHome = Get-IBMInstallationManagerHome

        if((Test-Path($this.InstallationDirectory)) -and ($iimHome) -and (Test-Path($iimHome))) {
            $iimSWTagFile = Join-Path -Path $this.InstallationDirectory -ChildPath "properties\version\*.swtag"
            if(Test-Path($iimSWTagFile)) {
                Write-Debug "IBM Installation Manager is Present"
                $CurrentRsrc.Ensure = [Ensure]::Present
                $CurrentRsrc.InstallationDirectory = $iimHome
                Write-Debug "IBM Installation Manager Directory: $($CurrentRsrc.InstallationDirectory)"
                $CurrentRsrc.Version = Get-IBMInstallationManagerVersion
                Write-Debug "IBM Installation Manager Version: $($CurrentRsrc.Version)"
                $CurrentRsrc.TempDir = Get-IBMInstallationManagerTempDir
            }
        } else {
            Write-Verbose "IBM Installation Manager is NOT Present"
        }

        return $CurrentRsrc
    }
}

[DscResource()]
class cIBMProductInstall {
    
    [DscProperty(Mandatory)]
    [Ensure] $Ensure
    
    [DscProperty(Key)]
    [String] $Version
    
    [DscProperty()]
    [String] $InstallationDirectory
    
    [DscProperty()]
    [String] $IMSharedLocation = "C:\IBM\IMShared"
    
    [DscProperty()]
    [StartupType] $StartupType = [StartupType]::Automatic
    
    [DscProperty()]
    [PSCredential] $WindowsServiceAccount
    
    [DscProperty()]
    [String] $InstallMediaConfig
    
    [DscProperty()]
    [String] $ResponseFileTemplate

    [DscProperty()]
    [String] $SourcePath
    
    [DscProperty()]
    [PSCredential] $SourcePathCredential

    [DscProperty()]
    [String] $ProductName = ""
    
    [DscProperty()]
    [Hashtable] $CustomVariables = @{}

    [String] $BaseDSCPath = $PSScriptRoot
    [String] $MediaConfigFolder = "InstallMediaConfig"
    [String] $ResponseFileTemplatesFolder = "ResponseFileTemplates"
    [Int] $VersionDepth = 3

    [Void] PreSet() {}

    [Void] PostSet() {}

    [bool] PostTest() {
        Return $true
    }

    [Hashtable] PopulateVariables() {
        [Hashtable] $vars = @{}
        $vars.Add("sharedLocation", $this.IMSharedLocation)
        $vars.Add("installLocation", $this.InstallationDirectory)
        $vars += $this.CustomVariables
        Return $vars
    }

    [bool] InstallProduct([string]$mediaConfig, [string]$respFileTemplate) {
        $installed = $false
        if ([string]::IsNullOrEmpty($mediaConfig) -or [string]::IsNullOrEmpty($respFileTemplate)) {
            Write-Error "Media Config or Response File Template not specified"
            Return $false
        } else {
            Write-Verbose "Starting installation of IBM Product: $($this.ProductName)" -Verbose
            $varsToReplace = $this.PopulateVariables()
            $installed = Install-IBMProduct -InstallMediaConfig $mediaConfig `
                -ResponseFileTemplate $respFileTemplate -Variables $varsToReplace `
                -SourcePath $this.SourcePath -SourcePathCredential $this.SourcePathCredential -ErrorAction Stop
            if ($installed) {
                Write-Verbose "IBM Product: $($this.ProductName) Installed Successfully" -Verbose
            } else {
                Write-Error "Error occurred during installation, please check IIM logs for more information"
            }
        }
        Return $installed
    }

    [Version] GetIBMProductVersion() {
        Write-Warning "This method should be overridden"
        Return $null
    }

    [String] GetIBMProductInstallLocation() {
        Write-Warning "This method should be overridden"
        Return $null
    }

    <#
        Installs an IBM Product
    #>
    [void] Set () {
        try {
            if ($this.Ensure -eq [Ensure]::Present) {
                $this.PreSet()
                $ibmProductRsrc = $this.Get()
                if ($ibmProductRsrc.InstallationDirectory -and (Test-Path $ibmProductRsrc.InstallationDirectory)) {
                    Write-Error "IBM Product: $($this.ProductName) already installed. Uninstall first before attempting to install it again"
                } else {
                    if (!($this.InstallMediaConfig)) {
                        $this.InstallMediaConfig = Join-Path -Path $this.BaseDSCPath -ChildPath "$($this.MediaConfigFolder)\$($this.ProductName)-$($this.Version).xml"
                    }
                    if (!($this.ResponseFileTemplate)) {
                        $this.ResponseFileTemplate = Join-Path -Path $this.BaseDSCPath -ChildPath "$($this.ResponseFileTemplatesFolder)\$($this.ProductName)-$($this.Version).xml"
                    }
                    if ($this.InstallProduct($this.InstallMediaConfig, $this.ResponseFileTemplate)) {
                        $this.PostSet()
                    } else {
                        Write-Error "Unable to install IBM Product: $($this.ProductName)"
                    }
                }
            } else {
                Write-Verbose "Uninstalling IBM Product: $($this.ProductName) (Not Yet Implemented)"
            }
        } catch {
            Write-Error -ErrorRecord $_ -ErrorAction Stop
        }
    }

    <#
        Performs test to check if IBM Product is in the desired state, includes 
        validation of installation directory and version
    #>
    [bool] Test () {
        Write-Verbose "Checking for IBM Product installation"
        $ibmProductConfiguredCorrectly = $false
        $ibmProductRsrc = $this.Get()
        
        if (($ibmProductRsrc.Ensure -eq $this.Ensure) -and ($ibmProductRsrc.Ensure -eq [Ensure]::Present)) {
            $sameVersion = ($ibmProductRsrc.Version -eq $this.Version)
            if (!($sameVersion)) {
                $currVersionObj = (New-Object -TypeName System.Version -ArgumentList $ibmProductRsrc.Version)
                $newVersionObj = (New-Object -TypeName System.Version -ArgumentList $this.Version)
                $sameVersion = (($currVersionObj.ToString($this.VersionDepth)) -eq ($newVersionObj.ToString($this.VersionDepth)))
            }
            if ($sameVersion) {
                if (((Get-Item($ibmProductRsrc.InstallationDirectory)).Name -eq 
                    (Get-Item($this.InstallationDirectory)).Name) -and (
                    (Get-Item($ibmProductRsrc.InstallationDirectory)).Parent.FullName -eq 
                    (Get-Item($this.InstallationDirectory)).Parent.FullName)) {
                    Write-Verbose "IBM Product: $($this.ProductName) has correct version and install directory"
                    $ibmProductConfiguredCorrectly = $this.PostTest()
                }
            }
        } elseif (($ibmProductRsrc.Ensure -eq $this.Ensure) -and ($ibmProductRsrc.Ensure -eq [Ensure]::Absent)) {
            $ibmProductConfiguredCorrectly = $true
        }

        if (!($ibmProductConfiguredCorrectly)) {
            Write-Verbose "IBM Product: $($this.ProductName) not configured correctly"
        }
        
        return $ibmProductConfiguredCorrectly
    }

    <#
        Retrieves information about the IBM product
    #>
    [cIBMProductInstall] Get () {
        $CurrentRsrc = [cIBMProductInstall]::new()
        $CurrentRsrc.Ensure = [Ensure]::Absent
        $CurrentRsrc.InstallationDirectory = $null
        $CurrentRsrc.Version = $null
        
        $CurrentRsrc.InstallationDirectory = $this.GetIBMProductInstallLocation()
        
        if($CurrentRsrc.InstallationDirectory -and (Test-Path($CurrentRsrc.InstallationDirectory))) {
            $VersionObj = $this.GetIBMProductVersion()
            if ($VersionObj) {
                Write-Verbose "IBM Product: $($this.ProductName) is Present"
                $CurrentRsrc.Ensure = [Ensure]::Present
                $CurrentRsrc.Version = $VersionObj.ToString($this.VersionDepth)
            } else {
                Write-Warning "Unable to retrieve version information from the IBM Product: $($this.ProductName) installed"
            }
        } else {
            Write-Verbose "IBM Product: $($this.ProductName) is NOT Present"
        }

        return $CurrentRsrc
    }
}