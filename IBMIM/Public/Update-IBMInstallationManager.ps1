##############################################################################################################
# Update-IBMInstallationManager
#   Updates IBM Installation Mananger to a newer version
##############################################################################################################
Function Update-IBMInstallationManager() {
    [CmdletBinding(SupportsShouldProcess=$True,ConfirmImpact="Medium")]
    param (
    	[parameter(Mandatory = $true)]
		[System.String]
    	$iimHome,

    	[parameter(Mandatory = $true)]
		[System.String]
		$iimMedia,
        
        [parameter(Mandatory = $true)]
        [System.String]
		$Version,

        [System.Management.Automation.PSCredential]
		$iimMediaCredential,
        
		[System.String]
		$TempDir
	)

    PROCESS {
        if ($PSCmdLet.ShouldProcess($Path)) {
            Write-Verbose "Updating IBM Installation Manager"

            #Make temp directory for IIM files
            $iimTempDir = $null
            if ($TempDir -and (Test-Path $TempDir)) {
                $iimTempDir = Join-Path $TempDir -ChildPath "iim_update"
            } else {
                $iimTempDir = Join-Path (Get-IBMTempDir) -ChildPath "iim_update"
            }

            $localMediaPath = Copy-RemoteItemLocally $iimMedia (Split-Path($iimTempDir)) $iimMediaCredential

            if ($localMediaPath -and (Test-Path $localMediaPath)) {
                if (!(Test-Path $iimTempDir)) {
                    New-Item -ItemType Directory -Force -Path $iimTempDir | Out-Null
                }
                $iimTempDir = Expand-ZipFile $localMediaPath $iimTempDir -Force -Clean

                $updateLog = Join-Path -Path (Split-Path($iimTempDir)) -ChildPath "IIM_update_log.txt"
                $repoFile = Join-Path -Path $iimTempDir -ChildPath "repository.config"
                
                $iimupdate_args = @("install", "com.ibm.cic.agent", 
                                    "-repositories", ($repoFile),
                                    "-preferences", "offering.service.repositories.areUsed=false", "-log", $updateLog, "-acceptLicense")

                # Update IIM
                $iimToolsDir = Join-Path -Path $iimTempDir -ChildPath "tools" 
                $iimCLExe = Join-Path -Path $iimToolsDir -ChildPath "imcl.exe"
                $updateProc = Invoke-ProcessHelper $iimCLExe $iimupdate_args $iimToolsDir
                
                if ($updateProc -and ($updateProc.ExitCode -eq 0)) {
                    $updatedVersion = (Get-ItemProperty(Get-IBMInstallationManagerRegistryPath)).version
                    
                    if($Version -eq $updatedVersion) {
                        Write-Verbose "IBM Installation Manager updated successfully"
                        Remove-ItemBackground -Path $iimTempDir
                    } else {
                        Write-Error "IBM Installation Manager was not updated.  Please check the update logs"
                    }
                } else {
                    $errorMsg = (&{if($updateProc) {$updateProc.StdOut} else {$null}})
                    Write-Error "An error occurred while updating IBM Installation Manager: $errorMsg"
                }
            }
        }
    }
}