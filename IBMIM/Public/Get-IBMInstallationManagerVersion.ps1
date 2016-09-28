##############################################################################################################
# Get-IBMInstallationManagerVersion
#   Returns the version of IIM if installed
##############################################################################################################
Function Get-IBMInstallationManagerVersion() {
    [CmdletBinding(SupportsShouldProcess=$False)]
    Param()
    
    $iimVersion = $null
    $iimPath = Get-IBMInstallationManagerRegistryPath
    
    if (($iimPath) -and (Test-Path($iimPath))) {
        $iimVersion = (Get-ItemProperty($iimPath)).version
    }
    
    Return $iimVersion
}