##############################################################################################################
# Install-IBMProductViaResponseFile
#   Installs and IBM Product based on the response file specified
##############################################################################################################
Function Install-IBMProductViaResponseFile() {
    [CmdletBinding(SupportsShouldProcess=$False)]
    param (
    	[parameter(Mandatory = $true)]
		[System.String]
    	$ResponseFile,

    	[parameter(Mandatory = $false)]
		[System.String]
		$InstallLog
	)

	Write-Verbose "Installing IBM Product via Response File"
    [bool] $installed = $false
    
    #Validate Parameters
    if (!(Test-Path($ResponseFile) -PathType Leaf)) {
        Write-Error "Parameter ResponseFile with value=$ResponseFile could not be found or is not a valid process path"
    } else {
        [string[]] $installArgs = @('input', $ResponseFile)
        $installed = Invoke-IBMInstallationManagerCmdLine $installArgs $InstallLog
    }
    Return $installed
}