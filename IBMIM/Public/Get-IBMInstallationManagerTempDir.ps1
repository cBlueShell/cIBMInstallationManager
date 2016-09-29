##############################################################################################################
# Get-IBMInstallationManagerTempDir
#   Retrieves the temporary directory that IBM Installation Manager uses for installing products
##############################################################################################################
Function Get-IBMInstallationManagerTempDir() {
    [CmdletBinding(SupportsShouldProcess=$False)]
    Param ()
    
    $tempDir = $null
    
    $iimHome = Get-IBMInstallationManagerHome
    if ($iimHome) {
        $iimIniPath = Join-Path -Path $iimHome -ChildPath "eclipse\IBMIM.ini"
        if (Test-Path $iimIniPath) {
            $iniFile = Get-Content $iimIniPath
            [string] $tmpdirJavaOption = "-Djava.io.tmpdir"
            foreach($line in $iniFile) {
                if ($line.Contains($tmpdirJavaOption)) {
                    $tempDir = $line.substring($line.IndexOf($tmpdirJavaOption)+$tmpdirJavaOption.Length+1)
                }
            }
        }
    }
    if ($tempDir -and !(Test-Path $tempDir)) {
        New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
    }
    
    Return $tempDir
}