##############################################################################################################
# Set-IBMInstallationManagerTempDir
#   Updates the temporary directory that IBM Installation Manager
##############################################################################################################
Function Set-IBMInstallationManagerTempDir() {
    [CmdletBinding(SupportsShouldProcess=$True,ConfirmImpact="Low")]
    Param (
        [parameter(Mandatory=$true,position=0)]
        [string]
        $tempDir
    )
    PROCESS {
        if ($PSCmdLet.ShouldProcess($Path)) {
            #Make Temp if not exists
            if(!(Test-Path $tempDir)){
                New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
            }
            $iimHome = Get-IBMInstallationManagerHome
            $iimIniPath = Join-Path -Path $iimHome -ChildPath "eclipse\IBMIM.ini"
            if (Test-Path $iimIniPath) {
                [string] $updatedIniFile = ""
                [bool] $afterVMArgs = $false
                [bool] $hasTempDir = $false
                $iniFile = Get-Content $iimIniPath
                
                foreach($line in $iniFile) {
                    if ($afterVMArgs) {
                        if ($line.Contains("java.io.tmpdir")) {
                            # Replace Temp Dir setting
                            $line = "-Djava.io.tmpdir=$tempDir"
                        } else {
                            # Append temp dir setting
                            $updatedIniFile += "-Djava.io.tmpdir=$tempDir`n"
                        }
                        $afterVMArgs = $false
                    }
                    if ($line.StartsWith("-vmargs")) {
                        $afterVMArgs = $true
                    }
                    if ([string]::IsNullOrEmpty($line)) {
                        $updatedIniFile += "$line"
                    } else {
                        $updatedIniFile += "$line`n"
                    }
                }
                $updatedIniFile | out-file "$iimIniPath" -encoding "ASCII"
            } else {
                Write-Error "$iimIniPath could not be located"
            }
        }
    }
}