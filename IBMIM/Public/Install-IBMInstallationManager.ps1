##############################################################################################################
# Install-IBMInstallationManager
#   Installs IBM Installation Mananger
##############################################################################################################
Function Install-IBMInstallationManager() {
    [CmdletBinding(SupportsShouldProcess=$False)]
    param (
    	[parameter(Mandatory = $true)]
		[System.String]
    	$iimHome,

    	[parameter(Mandatory = $true)]
		[System.String]
		$iimMedia, 

        [System.Management.Automation.PSCredential]
		$iimMediaCredential,
        
		[System.String]
		$TempDir
	)

	Write-Verbose "Installing IBM Installation Manager"

    #Make temp directory for IIM files
    $iimTempDir = $null
    if ($TempDir -and (Test-Path $TempDir)) {
        $iimTempDir = Join-Path $TempDir -ChildPath "iim_install"
    } else {
        $iimTempDir = Join-Path (Get-IBMTempDir) -ChildPath "iim_install"
    }

    $localMediaPath = Copy-RemoteItemLocally $iimMedia (Split-Path($iimTempDir)) $iimMediaCredential

    if (Test-Path $localMediaPath) {
        if (!(Test-Path $iimTempDir)) {
            New-Item -ItemType Directory -Force -Path $iimTempDir | Out-Null
        }
        $iimTempDir = Expand-ZipFile $localMediaPath $iimTempDir -Force -Clean

        $installLog = Join-Path -Path $iimTempDir -ChildPath "IIM_install_log.txt"
        $installExe = Join-Path -Path $iimTempDir -ChildPath "install.exe"
        $installArgs = @("--launcher.ini","silent-install.ini","-installationDirectory",$iimHome,"-log",$installLog,"-acceptLicense")
        $installProc = Invoke-ProcessHelper $installExe $installArgs $iimTempDir
        
        if ($installProc -and ($installProc.ExitCode -eq 0)) {
            if((Test-Path($iimHome)) -and (Get-IBMInstallationManagerRegistryPath)) {
                Write-Verbose "IBM Installation Manager installed successfully"
                Remove-ItemBackground -Path $iimTempDir
            } else {
                Write-Error "IBM Installation Manager was not installed.  Please check the installation logs"
            }
        } else {
            $errorMsg = (&{if($installProc) {$installProc.StdOut} else {$null}})
            Write-Error "An error occurred while installing IBM Installation Manager: $errorMsg"
        }
    } else {
        Write-Error "Unable to copy remote media locally to folder: $iimTempDir"
    }
}