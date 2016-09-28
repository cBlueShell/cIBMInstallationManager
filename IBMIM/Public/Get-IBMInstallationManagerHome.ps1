##############################################################################################################
# Get-IBMInstallationManagerHome
#   Returns the location where IBM Installation Manager is installed
##############################################################################################################
Function Get-IBMInstallationManagerHome() {
    [CmdletBinding(SupportsShouldProcess=$False)]
    Param()
    
    $iimPath = Get-IBMInstallationManagerRegistryPath
    
    if (($iimPath) -and (Test-Path($iimPath))) {
        $iimHome = (Get-ItemProperty($iimPath)).location
        if (Test-Path $iimHome) {
            Write-Debug "Get-IBMInstallationManagerHome returning $iimHome"
            Return $iimHome
        }
    }
    Return $null
}