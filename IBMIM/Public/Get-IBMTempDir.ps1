##############################################################################################################
# Get-IBMTempDir
#   Retrieves the current temporary directory used for IBM.  Fallsback to the environment temp directory
##############################################################################################################
Function Get-IBMTempDir() {
    [CmdletBinding(SupportsShouldProcess=$False)]
    Param ()
    
    $tempDir = Get-IBMInstallationManagerTempDir
    
    if (!$tempDir -or !(Test-Path $tempDir)) {
        $tempDir = $env:TEMP
    }
    
    Return $tempDir
}