##############################################################################################################
########                           IBM Installation Manager CmdLets                                  #########
##############################################################################################################
Import-Module $PSScriptRoot\Classes\IBMProductMedia.ps1 -ErrorAction Stop

# Global Variables / Resource Configuration
$IIM_PATH = "HKLM:\Software\IBM\Installation Manager"
$IIM_PATH_64 = "HKLM:\Software\Wow6432Node\IBM\Installation Manager"
$IIM_PATH_USER = "HKCU:\Software\IBM\Installation Manager"
$IIM_PATH_USER_64 = "HKCU:\Software\Wow6432Node\IBM\Installation Manager"
$IBM_PSDSC_SEQ_DEBUG = "IBM_PSDSC_SEQ_DEBUG"

##############################################################################################################
# Get-IBMInstallationManagerRegistryPath
#   Returns the registry path for IBM Installation Manager or $null if there isn't any
##############################################################################################################
Function Get-IBMInstallationManagerRegistryPath() {
    [CmdletBinding(SupportsShouldProcess=$False)]
    Param()
    
    $iimPath = $null
    if ([IntPtr]::Size -eq 8) {
        $iimPath = $IIM_PATH_64
        if (!(Test-Path($iimPath))) {
            $iimPath = $IIM_PATH_USER_64
            if (!(Test-Path($iimPath))) {
                $iimPath = $IIM_PATH
                if (!(Test-Path($iimPath))) {
                    $iimPath = $IIM_PATH_USER
                    if (!(Test-Path($iimPath))) {
                        $iimPath = $null
                    }
                }
            }
        }
    } else {
        $iimPath = $IIM_PATH
        if (!(Test-Path($iimPath))) {
            $iimPath = $IIM_PATH_USER
            if (!(Test-Path($iimPath))) {
                $iimPath = $null
            }
        }
    }
    
    Write-Debug "Get-IBMInstallationManagerRegistryPath returning path: $iimPath"
    
    Return $iimPath
}

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
    
    $sevenZipExe = Get-SevenZipExecutable
    if (!([string]::IsNullOrEmpty($sevenZipExe)) -and (Test-Path($sevenZipExe))) {
        Set-Alias zip $sevenZipExe

        #Make temp directory for IIM files
        $iimTempDir = $null
        if ($TempDir -and (Test-Path $TempDir)) {
            $iimTempDir = Join-Path $TempDir -ChildPath "iim_install"
        } else {
            $iimTempDir = Join-Path (Get-IBMTempDir) -ChildPath "iim_install"
        }
        
        Write-Verbose "Creating/Resteting temporary folder: $iimTempDir"
        if (Test-Path -Path $iimTempDir) {
            Remove-Item $iimTempDir -Recurse -Force
        }
        New-Item -ItemType directory -Path $iimTempDir | Out-Null

        $networkShare = $false
        if (($iimMedia.StartsWith("\\")) -and (!(Test-Path($iimMedia)))) {
            Write-Verbose "Network Share detected, need to map"
            Set-NetUse -SharePath $iimMedia -SharePathCredential $iimMediaCredential -Ensure "Present" | Out-Null
            $networkShare = $true
        }

        try {
            if (!(Test-Path($iimMedia))) {
                Write-Error "Unable to access media: $iimMedia"
                Return $null
            }
            
            #Unzip in temp install folder
            Write-Verbose "Extracting installation files to $iimTempDir from $iimMedia"    
            zip x "-o$iimTempDir" $iimMedia | Out-Null
        
            $installLog = Join-Path -Path $iimTempDir -ChildPath "IIM_install_log.txt"
            $installExe = Join-Path -Path $iimTempDir -ChildPath "install.exe"
            $installArgs = @("--launcher.ini","silent-install.ini","-installationDirectory",$iimHome,"-log",$installLog,"-acceptLicense")
            $installProc = Invoke-ProcessHelper $installExe $installArgs $iimTempDir
            
            if ($installProc -and ($installProc.ExitCode -eq 0)) {
                if((Test-Path($iimHome)) -and (Get-IBMInstallationManagerRegistryPath)) {
                    Write-Verbose "IBM Installation Manager installed successfully"
                    
                    # Clean up / Workaround for AntiVirus issue - hangs while deleting files
                    Write-Verbose "Attempting to remove temporary installation files, after 1 minute the job will timeout and you may need to delete $iimTempDir directory manually."
                    $rmjob = Start-Job { param($tdir) Remove-Item $tdir -Recurse -Force -ErrorAction SilentlyContinue } -ArgumentList $iimTempDir
                    Wait-Job $rmjob -Timeout 60 | Out-Null
                    Stop-Job $rmjob | Out-Null
                    Receive-Job $rmjob | Out-Null
                    Remove-Job $rmjob | Out-Null
                } else {
                    Write-Error "IBM Installation Manager was not installed.  Please check the installation logs"
                }
            } else {
                $errorMsg = (&{if($installProc) {$installProc.StdOut} else {$null}})
                Write-Error "An error occurred while installing IBM Installation Manager: $errorMsg"
            }
        } finally {
            if ($networkShare) {
                Set-NetUse -SharePath $iimMedia -SharePathCredential $iimMediaCredential -Ensure "Absent" | Out-Null
            }
        }
    } else {
        Write-Error "IBM Installation Manager installation/update depends on 7-Zip, please ensure 7-Zip is installed first"
    }
}

##############################################################################################################
# Update-IBMInstallationManager
#   Updates IBM Installation Mananger to a newer version
##############################################################################################################
Function Update-IBMInstallationManager() {
    [CmdletBinding(SupportsShouldProcess=$False)]
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

	Write-Verbose "Updating IBM Installation Manager"
    
    $sevenZipExe = Get-SevenZipExecutable
    if (!([string]::IsNullOrEmpty($sevenZipExe)) -and (Test-Path($sevenZipExe))) {
        Set-Alias zip $sevenZipExe
        
        #Make temp directory for IIM files
        $iimTempDir = $null
        if ($TempDir -and (Test-Path $TempDir)) {
            $iimTempDir = Join-Path $TempDir -ChildPath "iim_update"
        } else {
            $iimTempDir = Join-Path (Get-IBMTempDir) -ChildPath "iim_update"
        }
        Write-Verbose "Creating/Resteting temporary folder: $iimTempDir"
        if (Test-Path -Path $iimTempDir) {
            Remove-Item $iimTempDir -Recurse -Force
        }
        New-Item -ItemType directory -Path $iimTempDir | Out-Null
        
        $networkShare = $false
        try {
            if (($iimMedia.StartsWith("\\")) -and (!(Test-Path($iimMedia)))) {
                Write-Verbose "Network Share detected, need to map"
                Set-NetUse -SharePath (Split-Path($iimMedia)) -SharePathCredential $iimMediaCredential -Ensure "Present" | Out-Null
                $networkShare = $true
            }
        } catch [System.UnauthorizedAccessException] {
            Write-Verbose "Network Share detected, need to map"
            Set-NetUse -SharePath (Split-Path($iimMedia)) -SharePathCredential $iimMediaCredential -Ensure "Present" | Out-Null
            $networkShare = $true
        }

        try {
            if (!(Test-Path($iimMedia))) {
                Write-Error "Unable to access media: $iimMedia"
                Return $null
            }
            
            #Unzip in temp install folder
            Write-Verbose "Extracting installation files to $iimTempDir from $iimMedia"
            zip x "-o$iimTempDir" $iimMedia | Out-Null
        
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
                    
                    # Clean up / Workaround for AntiVirus issue - hangs while deleting files
                    Write-Verbose "Attempting to remove temporary installation files, after 1 minute the job will timeout and you may need to delete $iimTempDir directory manually."
                    $rmjob = Start-Job { param($tdir) Remove-Item $tdir -Recurse -Force -ErrorAction SilentlyContinue } -ArgumentList $iimTempDir
                    Wait-Job $rmjob -Timeout 60 | Out-Null
                    Stop-Job $rmjob | Out-Null
                    Receive-Job $rmjob | Out-Null
                    Remove-Job $rmjob | Out-Null
                } else {
                    Write-Error "IBM Installation Manager was not updated.  Please check the update logs"
                }
            } else {
                $errorMsg = (&{if($updateProc) {$updateProc.StdOut} else {$null}})
                Write-Error "An error occurred while updating IBM Installation Manager: $errorMsg"
            }
        } finally {
            if ($networkShare) {
                Set-NetUse -SharePath (Split-Path($iimMedia)) -SharePathCredential $iimMediaCredential -Ensure "Absent" | Out-Null
            }
        }
    } else {
        Write-Error "IBM Installation Manager installation/update depends on 7-Zip, please ensure 7-Zip is installed first"
    }
}

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
                    # Clean up / Workaround for AntiVirus issue - hangs while deleting files
                    Write-Verbose "Attempting to remove temporary installation files, after 1 minute the job will timeout and you may need to delete $ibmprodTempDir directory manually."
                    $rmjob = Start-Job { param($tdir) Remove-Item $tdir -Recurse -Force -ErrorAction SilentlyContinue } -ArgumentList $ibmprodTempDir
                    Wait-Job $rmjob -Timeout 60 | Out-Null
                    Stop-Job $rmjob | Out-Null
                    Receive-Job $rmjob | Out-Null
                    Remove-Job $rmjob | Out-Null
                }
            }
        }
    }
    
    Return $installed
}

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
            # Clean up / Workaround for AntiVirus issue - hangs while deleting files
            Write-Verbose "Attempting to remove temporary installation files, after 1 minute the job will timeout and you may need to delete $ibmTempDir directory manually."
            $rmjob = Start-Job { param($tdir) Remove-Item $tdir -Recurse -Force -ErrorAction SilentlyContinue } -ArgumentList $ibmTempDir
            Wait-Job $rmjob -Timeout 60 | Out-Null
            Stop-Job $rmjob | Out-Null
            Receive-Job $rmjob | Out-Null
            Remove-Job $rmjob | Out-Null
        }
    } else {
        Write-Error "Unable to extrace media"
    }
    
    Return $installed
}

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

##############################################################################################################
# Invoke-IBMInstallationManagerCmdLine
#   Invokes the IBM InstallationManager Command Line (imcl) - accepts licenses automatically
##############################################################################################################
Function Invoke-IBMInstallationManagerCmdLine() {
    [CmdletBinding(SupportsShouldProcess=$False)]
    param (
        [parameter(Mandatory=$true,position=0)]
		[System.String[]]
    	$Arguments,
        
        [parameter(Mandatory=$false,position=1)]
		[System.String]
		$OutputLog
	)
    [bool] $success = $false
    
    #Validate Parameters
    $iimHome = Get-IBMInstallationManagerHome
    if (!(Test-Path($iimHome) -PathType Container)) {
        Write-Error "IBM Installation Manager Home Location is invalid: $iimHome"
    } else {
        #Setup Process
        $imclExe = Join-Path -Path $iimHome -ChildPath "\eclipse\tools\imcl.exe"
        $Arguments += '-acceptLicense'
        if ($OutputLog -and (!([string]::IsNullOrEmpty($OutputLog)))) {
            [string] $logArg = '"' + $OutputLog + '"'
            $Arguments += @('-log', $logArg)
        }
        $installProc = Invoke-ProcessHelper $imclExe $Arguments
        if ($installProc -and ($installProc.ExitCode -eq 0)) {
            $stdout = $installProc.StdOut
            if ($stdout) {
                # Look for any potential error codes on stdout (based on IBM's error message IDs)
                $errorFound = $stdout -match "CRIM[A-Z]?\d{0,5}?E"
                if ($errorFound) {
                    Write-Error "An error was found while invoking the IIM cmd line: $stdout"
                } else {
                    # Look for any potential error codes on stdout (based on IBM's error message IDs)
                    $warningFound = $stdout -match "CRIM[A-Z]?\d{0,5}?W"
                    if ($warningFound) {
                        Write-Warning "Warning detected, please look at the IIM log for more information: $OutputLog"
                    } else {
                        Write-Verbose "imcl.exe ran successfully"
                    }
                    $success = $true
                }
            }
        } else {
            $errorMsg = (&{if($installProc.StdErr) {$installProc.StdErr} else {$installProc.StdOut}})
            Write-Error "An error occurred while invoking the IIM cmd line: $errorMsg"
        }
    }
    Return $success
}

##############################################################################################################
# New-IBMInstallationManagerResponseFile
#   Generates a new response file based on the template specified.
#      - Updates the repository locations from the ProductMedia parameter along with the extracted media folder
#      - Updates variables in response file from the Variables hashtable
#      - Converts credential variables to hashed passwords
##############################################################################################################
Function New-IBMInstallationManagerResponseFile {
    param (
        [parameter(Mandatory = $true)]
        [String]
        $TargetPath,
        
        [parameter(Mandatory = $true)]
        [String]
        $ResponseFileTemplate,

        [parameter(Mandatory = $true)]
        [IBMProductMedia]
        $ProductMedia,
        
        [parameter(Mandatory = $true)]
        [String]
        $ExtractedMediaDirectory,
        
        [parameter(Mandatory = $false)]
        [Hashtable]
        $Variables
    )
    
    $fileCreated = $false
    Write-Verbose "Creating new response file from template: $ResponseFileTemplate"

    if (([string]::IsNullOrEmpty($ResponseFileTemplate)) -and (!(Test-Path($ResponseFileTemplate)))) {
        Write-Verbose "Response File template not found: $ResponseFileTemplate"
        Return $false
    }
    
    [XML] $responseFileXML = Get-Content $ResponseFileTemplate
    $rootNode = $responseFileXML.ChildNodes[1]

    #Update response file with the product specific repository locations
    $serverNode = $responseFileXML.SelectSingleNode("//agent-input/server")
    if (!($serverNode)) {
        $serverNode = $responseFileXML.CreateElement("server")
        $rootNode.InsertBefore($serverNode, $rootNode.FirstChild) | Out-Null
    } else {
        $serverNode.RemoveAll()
    }
    $repositoryList = $ProductMedia.GetRepositoryLocations($ExtractedMediaDirectory, $true)
    
    if ($repositoryList -and ($repositoryList.Count -gt 0)) {
        Foreach ($repositoryLocation in $repositoryList) {
            $repositoryNode = $responseFileXML.CreateElement("repository")
            $locationAttr = $responseFileXML.CreateAttribute("location")
            $locationAttr.Value = $repositoryLocation
            $repositoryNode.Attributes.Append($locationAttr) | Out-Null
            $serverNode.AppendChild($repositoryNode) | Out-Null
        }
        
        #Update variables in new response files with the values provided
        $variablesNode = $responseFileXML.SelectSingleNode("//agent-input/variables")
        if (!($variablesNode) -and $Variables -and ($Variables.Count -gt 0)) {
            $variablesNode = $responseFileXML.CreateElement("variables")
            $rootNode.InsertBefore($variablesNode, $rootNode.FirstChild) | Out-Null
        }

        Foreach ($varName in $Variables.Keys) {
            $varType = ($Variables[$varName]).GetType().Name
            $varValue = $null
            if ($varType -eq "String") {
                $varValue = $Variables[$varName]
            } elseif ($varType -eq "PSCredential") {
                # Credential object passed as variable, hash its password and added to response file
                $cred = [System.Management.Automation.PSCredential] $Variables[$varName]
                [string]$hashedPwd = ConvertTo-HashedPassword $cred
                if (!([string]::IsNullOrEmpty($hashedPwd)))
                {
                    $varValue = $hashedPwd
                }
            } elseif ($varType -eq "Boolean") {
                $varValue = (&{if($Variables[$varName]) {"true"} else {"false"}})
            } else {
                $varValue = $Variables[$varName]
            }

            $varNode = $responseFileXML.SelectSingleNode("//agent-input/variables/variable[@name='$varName']")
            if ($varNode) {
                $varValueAttr = $varNode.Attributes.GetNamedItem("value")
                $varValueAttr.Value = $varValue
            } else {
                $varNode = $responseFileXML.CreateElement("variable")
                $varNameAttr = $responseFileXML.CreateAttribute("name")
                $varValueAttr = $responseFileXML.CreateAttribute("value")
                $varNameAttr.Value = $varName
                $varValueAttr.Value = $varValue
                $varNode.Attributes.Append($varNameAttr) | Out-Null
                $varNode.Attributes.Append($varValueAttr) | Out-Null
                $variablesNode.AppendChild($varNode) | Out-Null
            }
        }
    } else {
        Write-Error "No media repositories found in the extracted media folder based on the ProductMedia specified"
        $responseFileXML = $false
    }
    
    try {
        Write-Verbose "Saving new response file to the following location: $TargetPath"
        $responseFileXML.Save($TargetPath) | Out-Null
        $fileCreated = $true
    } catch {
        Write-Error "Unable to save the response file to the target location specified: $TargetPath"
    }
    
    Return $fileCreated
}

##############################################################################################################
# Set-IBMInstallationManagerTempDir
#   Updates the temporary directory that IBM Installation Manager
##############################################################################################################
Function Set-IBMInstallationManagerTempDir() {
    [CmdletBinding(SupportsShouldProcess=$False)]
    Param (
        [parameter(Mandatory=$true,position=0)]
        [string]
        $tempDir
    )
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
        $iniFile = gc $iimIniPath
        
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
            $iniFile = gc $iimIniPath
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

##############################################################################################################
# ConvertTo-HashedPassword
#   Generates a hashed password from password specified using the IBM Installation Manager Command Line
##############################################################################################################
Function ConvertTo-HashedPassword() {
    [CmdletBinding(SupportsShouldProcess=$False)]
    Param (
        [Parameter(Mandatory=$True, Position=0)]
        [System.Management.Automation.PSCredential]
        $UserCredential
    )

    Write-Verbose "ConvertTo-HashedPassword called"

    if (Test-Path($IIM_PATH)) {
        $iimHome = (Get-ItemProperty($IIM_PATH)).location
        $iimcPath = Join-Path -Path $iimHome -ChildPath "eclipse\IBMIMc.exe"
        if (Test-Path($iimcPath)) {
            $plainpwd = $UserCredential.GetNetworkCredential().Password
            $iimExpression = '& ' + $iimcPath + ' -noSplash -silent encryptstring "' + $plainpwd + '"'
            $hashedPwd = Invoke-Expression $iimExpression
            Write-Verbose "ConvertTo-HashedPassword returning hashed password"
            Return $hashedPwd
        }
    }

    Write-Verbose "ConvertTo-HashedPassword did not return anything"
}

##############################################################################################################
# Get-SevenZipExecutable
#   Gets the path to the 7-zip executable if present, otherwise returns null
##############################################################################################################
Function Get-SevenZipExecutable {
    [CmdletBinding(SupportsShouldProcess=$False)]
    Param()
    
	$sevenZipExe = $null
	if (Test-Path("HKLM:\Software\7-Zip")) {
		$sevenZipExe = (Get-ItemProperty -Path "HKLM:\SOFTWARE\7-Zip").Path + "7z.exe"
	} else {
		if (Test-Path("HKCU:\Software\7-Zip")) {
			$sevenZipExe = (Get-ItemProperty -Path "HKCU:\SOFTWARE\7-Zip").Path + "7z.exe"
		}
	}
	return $sevenZipExe
}

##############################################################################################################
# Invoke-ProcessHelper
#   Process utility method that provides error handling, output buffering, etc
##############################################################################################################
Function Invoke-ProcessHelper() {
[CmdletBinding(SupportsShouldProcess=$False)]
    Param (
        [Parameter(Mandatory=$True, Position=0)]
        [String]
        [ValidateNotNullOrEmpty()]
        $ProcessFileName,

        [Parameter(Mandatory=$False, Position=1)]
        [String[]]
        $ProcessArguments,

        [Parameter(Mandatory=$False, Position=2)]
        [String]
        $WorkingDirectory,
		
        [switch]
        $DiscardStandardOut,

        [switch]
        $DiscardStandardErr,
        
        [switch]
        $LogToFile,
        
        [switch]
        $RunasAdmin
    )
	$currentLocation = Get-Location
    #Validate Parameters
    if (!(Test-Path($ProcessFileName) -PathType Leaf)) {
        Write-Error "Parameter ProcessFileName with value=$ProcessFileName could not be found or is not a valid process path"
    }
    #Compose procStartInfo
    $procStartInfo = New-object System.Diagnostics.ProcessStartInfo
    $procStartInfo.FileName = $ProcessFileName
    $procStartInfo.CreateNoWindow = $true
    $procStartInfo.WindowStyle = "Hidden"
    $procStartInfo.UseShellExecute = $false
    if(!($LogToFile.isPresent)){
    	$procStartInfo.RedirectStandardOutput = (!($DiscardStandardOut.IsPresent))
  		$procStartInfo.RedirectStandardError = (!($DiscardStandardErr.IsPresent))
    }

    if($RunasAdmin.isPresent){
    	if (([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")){   
			Write-Verbose("Invoke-ProcessHelper Run as Administrator")
            $procStartInfo.Verb = "runas"
		}else{
			Write-Warning("Current User doesn't have administrator privillages")
		}
		    	
    }
    
    #Log handling
    if($LogToFile.isPresent){
	    $tmpLog = Join-Path (Get-IBMTempDir) "Invoke-Process-$(get-date -f yyyyMMddHHmmss)-$(Get-Random).tmp"
	    $stdLog = ($tmpLog + ".std")
	    $errLog = ($tmpLog + ".err")
	    $ProcessArguments += @("1> $stdLog","2> $errLog")
    }
    
    if (($ProcessArguments -ne $null) -and ($ProcessArguments.Count -gt 0)) {
        $procStartInfo.Arguments = $ProcessArguments
    }
    if ($WorkingDirectory -and (Test-Path $WorkingDirectory)) {
        Set-Location $WorkingDirectory
        $procStartInfo.WorkingDirectory = $WorkingDirectory
    }
    Write-Verbose ("Invoke-ProcessHelper executing: $WorkingDirectory>$ProcessFileName")
    $exitcode = $null 
    $stdout = $null
    $stderr = $null
    Try {
        $process = New-Object System.Diagnostics.Process
        Write-Debug ("procStartInfo:"+($procStartInfo | Out-String))
        $process.StartInfo = $procStartInfo
        $process.Start() | Out-Null
        	
        if(!($LogToFile.isPresent)){
			if (!($DiscardStandardOut)) {
				$stdout = $process.StandardOutput.ReadToEnd()
			}
			if (!($DiscardStandardErr)) {
				$stderr = $process.StandardError.ReadToEnd()
			}
        }
        
        $process.WaitForExit()
        $exitcode = $process.ExitCode
    } Catch {
	    Write-Error "Invoke-ProcessHelper FAILED $($_.Exception | Out-String)"
    } finally {
        # Set location back
        if ($WorkingDirectory -and (Test-Path $WorkingDirectory)) {
            Set-Location $currentLocation
        }
		if($LogToFile.isPresent){
	        if(Test-Path($stdLog)){
	        	$stdout = Get-Content $stdLog | Out-String
	            Remove-Item $stdLog -Force
	        }
	        
	        if(Test-Path($errLog)){
	        	$stderr = Get-Content $errLog | Out-String
	            Remove-Item $errLog -Force
	        }
		}
    }
    
    return [PSCustomObject] @{
        StdOut = $stdout
        StdErr = $stderr
        ExitCode = $exitcode
    }
}

##############################################################################################################
# Get-CredentialBaseName
#   Returns the username of a credential object.  If the credential object is a distringuished name the first
#   part of the user object is used
##############################################################################################################
Function Get-CredentialBaseName {
    [CmdletBinding(SupportsShouldProcess=$False)]
    param ([parameter(Mandatory)][PSCredential] $UserCredential)
    
    [string] $credBaseName = Get-UserBaseName ($UserCredential.UserName)
    Return $credBaseName
}

##############################################################################################################
# Get-UserBaseName
#   Returns the base part of the username given a full username.  If its a distringuished name the first part
#   of the user object is used
##############################################################################################################
Function Get-UserBaseName {
    [CmdletBinding(SupportsShouldProcess=$False)]
    param ([parameter(Mandatory)][String]$UserName)
    
    [string] $credBaseName = $UserName
    if ($credBaseName.Contains(",")) {
        $credParts = $credBaseName.Split(",")
        if ($credParts -and ($credParts.Count -gt 0)) {
            $credBaseName = $credParts[0].Substring(($credParts[0].IndexOf('='))+1)
        } else {
            Write-Error "Unable to parse username $credBaseName"
        }
    } elseif ($credBaseName.Contains('\')) {
        $credBaseName = $credBaseName.Substring(($credBaseName.IndexOf('\'))+1)
    }
    Return $credBaseName
}

##############################################################################################################
# Set-NetUse
#   Mounts or Unmounts a file share via "net use" using the specified credentials 
##############################################################################################################
Function Set-NetUse {
    [CmdletBinding(SupportsShouldProcess=$False)]
    param (   
        [parameter(Mandatory = $true)]
        [string] $SharePath,
        
        [parameter(Mandatory = $false)]
        [PSCredential] $SharePathCredential,
        
        [string] $Ensure = "Present",
        
        [switch] $MapToDrive
    )
    
    [string] $randomDrive = $null

    Write-Verbose -Message "NetUse set share $SharePath ..."

    if ($Ensure -eq "Absent") {
        $cmd = 'net use "' + $SharePath + '" /DELETE'
    } else {
        $credCmdOption = ""
        if ($SharePathCredential) {
            $cred = $SharePathCredential.GetNetworkCredential()
            $pwd = $cred.Password
            $user = $cred.UserName
            if ($cred.Domain) {
                $user = $cred.Domain + "\" + $cred.UserName
            }
            $credCmdOption = " $pwd /user:$user"
        }
        
        if ($MapToDrive) {
            $randomDrive = Get-AvailableDrive
            $cmd = 'net use ' + $randomDrive + ' "' + $SharePath + '"' + $credCmdOption
        } else {
            $cmd = 'net use "' + $SharePath + '"' + $credCmdOption
        }
    }

    Invoke-Expression $cmd | Out-Null
    
    Return $randomDrive
}

##############################################################################################################
# Get-AvailableDrive
#   Get a random Drive letter.
##############################################################################################################
Function Get-AvailableDrive{
    $used   = Get-PSDrive | Select-Object -Expand Name |
          Where-Object { $_.Length -eq 1 }
    $unused = 90..65 | ForEach-Object { [string][char]$_ } |
              Where-Object { $used -notcontains $_ }
    $drive  = $unused[(Get-Random -Minimum 0 -Maximum $unused.Count)]
    return $drive
}

##############################################################################################################
# Set-JavaProperties
#   Updates a java property file based on the provided hashtable.  It allows to either append new Properties
#   or only modify existing ones.
##############################################################################################################
Function Set-JavaProperties() {
    [CmdletBinding(SupportsShouldProcess=$False)]
    param (
        [parameter(Mandatory=$true,position=0)]
        [String]
        $PropertyFilePath,

        [parameter(Mandatory=$true,position=1)]
        [Hashtable]
        $Properties,

        [switch]
        $DoNotAppend
    )

	[string] $finalFile = ""
    [string[]] $updatedProps = @()
	
	if (Test-Path $PropertyFilePath) {
		$file = gc $PropertyFilePath
		
		foreach($line in $file) {
			if ((!($line.StartsWith('#'))) -and
				(!($line.StartsWith(';'))) -and
				(!($line.StartsWith(";"))) -and
				(!($line.StartsWith('`'))) -and
				(($line.Contains('=')))) {
				$property=$line.split('=')[0]

                $Properties.Keys | % {
                    $propValue = $Properties.Item($_)
                    if ($_ -eq $property)
                    {
					    Write-Debug "Updated property: $_=$propValue"
					    $line = "$_=$propValue"
                        $updatedProps += $_
				    }
                }
			}
            if ([string]::IsNullOrEmpty($line)) {
                $finalFile += "$line"
            } else {
                $finalFile += "$line`n"
            }
		}
        if (!($DoNotAppend)) {
            # Properties that were not updated will be added to the end of the file
            $Properties.Keys | % {
                if (!($updatedProps.Contains($_))) {
                    $propValue = $Properties.Item($_)
                    Write-Debug "New property: $_=$propValue"
                    $line = "$_=$propValue"
                    $finalFile += "$line`n"
                }
            }
        }
		$finalFile | out-file "$PropertyFilePath" -encoding "ASCII"
	} else {
		Write-Error "Java Property file: $PropertyFilePath not found"
	}
}

##############################################################################################################
# Get-JavaProperties
#   Reads a Java-style Properties file and returns a hashtable of its content (excludes comments) 
##############################################################################################################
Function Get-JavaProperties() {
    [CmdletBinding(SupportsShouldProcess=$False)]
    param (
        [parameter(Mandatory=$true,position=0)]
        [string]
        $PropertyFilePath,

        [parameter(Mandatory=$false,position=1)]
        [string[]]
        $PropertyList
    )

    [hashtable] $props = @{}
	
	if (Test-Path $PropertyFilePath){
		$file = gc $PropertyFilePath
		
		foreach($line in $file) {
			if ((!($line.StartsWith('#'))) -and
				(!($line.StartsWith(';'))) -and
				(!($line.StartsWith(";"))) -and
				(!($line.StartsWith('`'))) -and
				(($line.Contains('=')))) {
				$propName=$line.split('=', 2)[0]
                $propValue=$line.split('=', 2)[1]

                if ($PropertyList) {
                    $PropertyList | % {
                        if ($_ -eq $propName){
                            $props.Add($propName, $propValue)
				        }
                    }
                } else {
                    $props.Add($propName, $propValue)
                }
			}
		}
	} else {
		Write-Error "Java Property file: $PropertyFilePath not found"
	}

    Return $props
}

##############################################################################################################
# Invoke-Batch
#   Process utility method that provides error handling, output buffering, etc
##############################################################################################################
Function Invoke-Batch(){
	[CmdletBinding(SupportsShouldProcess=$False)]
    Param (
        [Parameter(Mandatory=$True, Position=0)]
        [String]
        [ValidateNotNullOrEmpty()]
        $BatchFile,

        [Parameter(Mandatory=$False, Position=1)]
        [String[]]
        $Arguments,

        [Parameter(Mandatory=$False, Position=2)]
        [String]
        $WorkingDirectory,
        
        [Parameter(Mandatory=$False, Position=3)]
        [PSCredential]
        $RunAsCredential,
        
        [switch]
        $UseNewSession
    )
    $currentLocation = Get-Location
    
   	if (!(Test-Path $batchFile)) {
   		Write-Error ("$batchFile is not recognized as the name of a cmdlet, function, script file, or operable program. Check the spelling of the name, or if a path was included, verify that the path is correct and try again")
   	}
    if ($UseNewSession -and (!($RunAsCredential))) {
        Write-Error "In order to use a new session you need to specify the RunAsCredential"
    }
	Write-Debug ("Invoke-Batch:"+($batchFile + " " + ($arguments  | & {"$input"})))
    
	[PSCustomObject] $returnObject = $null
    
	Try{
		if ($WorkingDirectory -and (Test-Path $WorkingDirectory)) {
	        Set-Location $WorkingDirectory
	    }
		
		[Hashtable] $argList = @{
			"batchFile" = $BatchFile
			"arguments" = $Arguments
		}
		
		$scriptBlock = {
	    	param($argList)
	    	[Int] $exitcode
		    [String] $stdout
		    [String] $stderr
			    	
	    	$console = & $argList.batchFile $argList.arguments
	    	$exitcode = $LASTEXITCODE
		    if ($exitcode -eq 0) {
		       $stdout = $console
		    } else {
		       $stderr = $console
		    }
	    	
	    	return [PSCustomObject] @{
		        StdOut = $stdout
		        StdErr = $stderr
		        ExitCode = $exitcode
		    }
	    }
	    
	    if ($UseNewSession) {
	    	$session = New-PSSession -ComputerName $env:COMPUTERNAME -Credential $RunAsCredential
		    $returnObject = Invoke-Command -Session $session -ScriptBlock $scriptBlock -ArgumentList $argList
	    } else {
	    	$returnObject = Invoke-Command -ScriptBlock $scriptBlock -ArgumentList $argList
	    }
	} finally {
        # Set location back
        if ($WorkingDirectory -and (Test-Path $WorkingDirectory)) {
            Set-Location $currentLocation
        }
        
        if ($session){
        	Remove-PSSession $session
        }
    }
    
	return $returnObject
}



##############################################################################################################
# Enable-IBMPSDscSequenceDebug
#   Switch for Debuging IBM Powershell DSC executing sequence, when enabled, all the IBM DSC test method returns $true
##############################################################################################################
function Enable-IBMPSDscSequenceDebug([Bool] $Enable){
    if($Enable){
        Write-Warning "Enable IBM PowerShell Dsc Sequence Debugging, skip all IBM DSC config."
    }else{
        Write-Warning "Disable IBM PowerShell Dsc Sequence Debugging, All IBM DSC config will be effected."
    }
    
    [Environment]::SetEnvironmentVariable($IBM_PSDSC_SEQ_DEBUG, $Enable, "Machine");
}

##############################################################################################################
# Test-IBMPSDscSequenceDebug
#   Return $True if current IBM DSC sequence is in debug mode 
##############################################################################################################
function Test-IBMPSDscSequenceDebug(){
    $isDbg = $false
    $dbgFlag = [Environment]::GetEnvironmentVariable($IBM_PSDSC_SEQ_DEBUG)
    if($dbgFlag -and ($dbgFlag.ToUpper() -eq "TRUE")){
        $isDbg = $True
    }
    return $isDbg
}

##############################################################################################################
# Copy-RemoteItemLocal
#   Copy file/folder from local path or networkshared path  
##############################################################################################################
function Copy-RemoteItemLocal(){
    [CmdletBinding(SupportsShouldProcess=$False)]
    Param (
        [Parameter(Mandatory=$true,position=0)]
        [String] $Source,
        
        [Parameter(Mandatory=$false,position=1)]
        [String] $Destination,
        
        [Parameter(Mandatory=$false,position=2)]
        [PSCredential] $SourceCredential,
        
        [switch] $Directory
    )
	# Get temp file/folder if Destination is not providered    
    if(!$Destination){
    	$Destination = Get-IBMTempDir
    	if(!$Directory){
    		$Destination = (Join-Path $Destination -ChildPath (Split-Path -Path $Source -Leaf))
    	}
    }
    
	# Check the flag for networkshare
	$networkShare = $false
    try {
        if (($Source.StartsWith("\\")) -and (!(Test-Path $Source -ErrorAction SilentlyContinue))) {
            $networkShare = $true
        }
    } catch [System.UnauthorizedAccessException] {
        $networkShare = $true
    }
    # Go parent directory path for file copy 
    $sourceDir = $Source
    $destinationDir = $Destination
    if(!$Directory){
    	$sourceDir = (Split-Path($Source))
    	$destinationDir = (Split-Path($destinationDir))
    }
    
    # Mapping networkshare drive
    if($networkShare){
	    Write-Verbose "Network Share detected, need to map"
	    Set-NetUse -SharePath $sourceDir -SharePathCredential $SourceCredential -Ensure "Present" | Out-Null
    }
    
    try {
    	if( !$Directory ){
			Write-Verbose ("Copy File $Source $Destination")
			if(!(Test-Path($destinationDir))){
				New-Item -ItemType Directory -Force -Path $destinationDir | Out-Null
			}
        	Copy-Item $Source $Destination -Force | Out-Null
        } else {
        	Write-Verbose ("Copy Directory $Source $Destination")
        	if(!(Test-Path($destinationDir))){
				New-Item -ItemType Directory -Force -Path $destinationDir | Out-Null
			}
    		Get-ChildItem $sourceDir | % {Copy-Item -Path $_.FullName -Destination  $destinationDir -Force -Container -Recurse | Out-Null}
    	}
    } catch {
        $ErrorMessage = $_.Exception.Message
        Write-Error "An error occurred while copying files: $Source to $Destination \n Error Message: $ErrorMessage"
    } finally {
    	if($networkShare){
	        try {
	            Set-NetUse -SharePath $sourceDir -SharePathCredential $SourceCredential -Ensure "Absent" | Out-Null
	        } catch {
	            Write-Warning "Unable to disconnect share: $Source"
	        }
    	}
    }
    
    return $Destination
}