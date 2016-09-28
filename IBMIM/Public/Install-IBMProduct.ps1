##############################################################################################################
# Install-IBMProduct
#   Extracts product media, generates response file, installs the product, and finally performs some clean up
##############################################################################################################
Function Install-IBMProduct() {
    [CmdletBinding(SupportsShouldProcess=$False)]
    param (
        [parameter(Mandatory = $true)]
		[System.String]
		$InstallMediaConfig,
        
        [parameter(Mandatory = $true)]
		[System.String]
		$ResponseFileTemplate,
        
    	[parameter(Mandatory = $false)]
		[Hashtable]
    	$Variables,
        
    	[parameter(Mandatory = $true)]
		[System.String]
		$SourcePath,

        [System.Management.Automation.PSCredential]
		$SourcePathCredential
	)
    $installed = $false
	Write-Verbose "Installing IBM Product"
    
    if (!(Test-Path($InstallMediaConfig) -PathType Leaf)) {
        Write-Error "Invalid install media configuration: $InstallMediaConfig"
        Return $false
    }
    if (!(Test-Path($ResponseFileTemplate) -PathType Leaf)) {
        Write-Error "Invalid response file: $ResponseFileTemplate"
        Return $false
    }
    
    [IBMProductMedia] $productMediaConfig = $null
    [string] $productShortName = "ibmProduct"
    [string] $ibmprodTempDir = $null
    
    # Load media configuration and verify disk space for media extraction
    try {
        $productMediaConfig = Import-Clixml $InstallMediaConfig
        if ($productMediaConfig) {
            $productShortName = $productMediaConfig.ShortName
            #Make temp directory for IIM files
            $ibmprodTempDir = Join-Path -Path (Get-IBMTempDir) -ChildPath "$productShortName-install"
            if ($ibmprodTempDir -and (Test-Path $ibmprodTempDir)) {
                Remove-Item -Path $ibmprodTempDir -Recurse -Force
            }
            New-Item -ItemType Directory -Path $ibmprodTempDir | Out-Null
            $sizeNeededInMB = (($productMediaConfig.GetTotalSizeOnDisk()+500MB)/1MB)
            $targetDrive = ((Get-Item $ibmprodTempDir).PSDrive.Name + ":")
            $sizeAvailable = ((Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='$targetDrive'").FreeSpace / 1MB)
            if ($sizeNeededInMB -ge $sizeAvailable) {
                Write-Error "Insufficient disk space to extract the product media, size needed: $sizeNeededInMB MB size available: $sizeAvailable MB"
                Return $false
            }
        }
    } catch {
        Write-Error "Error occured while parsing file $InstallMediaConfig : $_"
    }
    
    if ($productMediaConfig) {
        # Extract media
        $mediaExtracted = $productMediaConfig.ExtractMedia($ibmprodTempDir, $SourcePath, $SourcePathCredential, $true, $false)
        if ($mediaExtracted) {
            # Create Response File
            $tempResponseFile = Join-Path -Path (Split-Path($ibmprodTempDir)) -ChildPath "$productShortName-responsefile-$(get-date -f yyyyMMddHHmmss).xml"
            $responseFileCreated = New-IBMInstallationManagerResponseFile -TargetPath $tempResponseFile `
                    -ResponseFileTemplate $ResponseFileTemplate -ProductMedia $productMediaConfig `
                    -ExtractedMediaDirectory $ibmprodTempDir -Variables $Variables
            if ($responseFileCreated) {
                # Install Product
                $productInstallLog = Join-Path -Path (Split-Path($ibmprodTempDir)) -ChildPath "$productShortName-install-$(get-date -f yyyyMMddHHmmss).log"
                $installed = Install-IBMProductViaResponseFile -ResponseFile $tempResponseFile -InstallLog $productInstallLog
                if ($installed) {
                    Remove-ItemBackground -Path $ibmprodTempDir
                }
            }
        }
    }
    
    Return $installed
}