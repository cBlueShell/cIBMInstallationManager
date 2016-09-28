##############################################################################################################
# Install-IBMProductViaCmdLine
#   Extracts product media, installs the product via cmdline, and finally performs some clean up
##############################################################################################################
Function Install-IBMProductViaCmdLine() {
    [CmdletBinding(SupportsShouldProcess=$False)]
    param (
        [parameter(Mandatory = $true)]
		[System.String]
		$ProductId,
        
        [parameter(Mandatory = $true)]
		[System.String]
		$InstallationDirectory,
        
    	[parameter(Mandatory = $false)]
		[Hashtable]
    	$Properties,
        
        [parameter(Mandatory = $true)]
		[System.String[]]
		$SourcePath,

        [System.Management.Automation.PSCredential]
		$SourcePathCredential
	)
    
    $installed = $false
	Write-Verbose "Installing IBM Product via Command Line"
    
    $ibmTempDir = Join-Path (Get-IBMTempDir) -ChildPath $ProductId
    
    [MediaFile[]] $mediaFiles = @()
    [string] $parentSourcePath = $null
    [bool] $singleRepo = $false
    foreach ($sourcePathLocation in $SourcePath) {
        [MediaFile] $mediaFile = [MediaFile]::new()
        if (!($singleRepo)) {
            $mediaFile.RepositoryConfigPath = "repository.config"
            $singleRepo = $true
        }
        $mediaFile.Name = (Split-Path $sourcePathLocation -Leaf)
        $mediaFiles += $mediaFile
        $parentSourcePath = (Split-Path $sourcePathLocation -Parent)
    }
    
    [IBMProductMedia] $productMedia = [IBMProductMedia]::new()
    $productMedia.Name = $ProductId
    $productMedia.MediaFiles = $mediaFiles
    Write-Verbose "Extracting media to $parentSourcePath"
    $mediaExtracted = $productMedia.ExtractMedia($ibmTempDir, $parentSourcePath, $SourcePathCredential, $true, $true)
    
    if ($mediaExtracted) {
        # Generate installation arguments
        $repos = $productMedia.GetRepositoryLocations($ibmTempDir, $true)
        [string] $productIdArg = '"' + $ProductId + '"'
        [string] $instDirArg = '"' + $InstallationDirectory + '"'
        [string] $reposArg = '"' + ($repos -join ' ') + '"'
        [string[]] $installArgs = @('install', $productIdArg, '-repositories', $reposArg, '-installationDirectory', $instDirArg)
        
        if ($Properties) {
            foreach ($property in $Properties) {
                $installArgs += ($property, $Properties[$property])
            }
        }
        
        $productInstallLog = Join-Path -Path (Split-Path($ibmTempDir)) -ChildPath "$ProductId-$(get-date -f yyyyMMddHHmmss).log"
        $installed = Invoke-IBMInstallationManagerCmdLine $installArgs $productInstallLog
        
        if ($installed) {
            Remove-ItemBackground -Path $ibmTempDir
        }
    } else {
        Write-Error "Unable to extrace media"
    }
    
    Return $installed
}