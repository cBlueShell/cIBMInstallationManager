<#
   PowerShell Classes to Model IBM Installation Media
   Key features: 
    - Model product configuration that can be extracted as Clixml files for later use
    - Expand IBM media from local or network shares
    - Get estimated size of the product installation
    - Get list of repository locations once media has been extracted
#>

<#
PowerShell Object Model for IBM Installation Manager media files.
Typically media files are zip files provided by IBM. 
#>
Class MediaFile {
    #Filename of the media file
    [String] $Name
    #(Optional) Location of the repository.config file within the zip file
    [String] $RepositoryConfigPath 
    #(Optional) Size of media on disk once extracted
    [Long] $SizeOnDisk
    #Zip files inside this media file that may need to be extracted
    [MediaFile[]] $SubMediaFiles
    
    <#
    Extract this media file to the target path (Requires 7-Zip)
    #>
    [Bool] ExtractMedia([String] $TargetPath, [String] $SourcePath, [bool] $DeepScan = $false) {
        Return ($this._ExtractMedia($this, $TargetPath, $SourcePath, $DeepScan))
    }

    hidden [Bool] _ExtractMedia([MediaFile] $mediaFile, [String] $TargetPath, [String] $SourcePath, [bool] $DeepScan) {
        $extracted = $false
        $fullMediaPath = Join-Path $SourcePath -ChildPath ($mediaFile.Name)
        if (!(Test-Path alias:zip)) {
            #Setup 7-Zip Alias
            $sevenZipExe = Get-SevenZipExecutable
            if (!([string]::IsNullOrEmpty($sevenZipExe)) -and (Test-Path($sevenZipExe))) {
                Set-Alias zip $sevenZipExe -Scope 'Script'
            } else {
                Write-Error "MediaFile depends on 7-Zip, please ensure 7-Zip is installed first"
                Return $false
            }
        }
        if (Test-Path($fullMediaPath)) {
            Write-Verbose "Extracting installation media from: $fullMediaPath"
            zip x "-o$TargetPath" "$fullMediaPath" | Out-Null
            # Some media have an additional zip file needed to extract, find it, expand it, and delete it to save disk space
            if ($DeepScan) {
                $childZipFiles = Get-ChildItem *.zip -Path $TargetPath
                foreach ($childZipFile in $childZipFiles) {
                    zip x "-o$TargetPath" $childZipFile.FullName | Out-Null
                    Remove-Item $childZipFile.FullName -force
                }
            }
            Write-Verbose "Completed extracting media files to directory: $TargetPath"
            $extracted = $true
        } else {
            Write-Error "Unable to access media files.  Media Path is: $SourcePath"
            $extracted = $false
        }
        
        if ($extracted) {
            if ($mediaFile.SubMediaFiles -and ($mediaFile.SubMediaFiles.Count -gt 0)) {
                Foreach ($subMediaFile in $mediaFile.SubMediaFiles) {
                    $extracted = $subMediaFile._ExtractMedia($subMediaFile, $TargetPath, $SourcePath)
                }
            }
        }
        Return $extracted
    }
    
    <#
    Returns a list of paths to the repository locations of this media file and its children
    #>
    [String[]] GetRepositoryLocations([String] $BasePath, [Bool] $Validate) {
        Return ($this._GetRepositoryLocations($this, $BasePath, $Validate))
    }

    hidden [String[]] _GetRepositoryLocations([MediaFile] $mediaFile, [String] $BasePath, [Bool] $Validate) {
        [String[]] $repositories = @();
        if ($mediaFile.RepositoryConfigPath) {
            $repositoryFullPath = Join-Path -Path $BasePath -ChildPath $mediaFile.RepositoryConfigPath
            if ($Validate) {
                try {
                    if (Test-Path($repositoryFullPath)) {
                        $repositories += $repositoryFullPath
                    } else {
                        Write-Error "Repository location not found: $repositoryFullPath"
                    }
                } catch [System.Exception] {
                    Write-Error "Repository location not found or could not be reached: $repositoryFullPath"
                }
            } else {
                $repositories += $repositoryFullPath
            }
        }
        if ($mediaFile.SubMediaFiles -and ($mediaFile.SubMediaFiles.Count -gt 0)) {
            Foreach ($subMediaFile in $mediaFile.SubMediaFiles) {
                $repositories += $subMediaFile._GetRepositoryLocations($subMediaFile, $BasePath, $Validate)
            }
        }
        Return $repositories
    }
}

<#
PowerShell Object Model for IBM Products that will be installed via IBM Installation Manager
#>
Class IBMProductMedia {
    # Name of the IBM product, should match offering name in repository.xml
    [String] $Name
    # (optional) Shortname of the IBM product, will be added to the path when media is extracted.
    [String] $ShortName
    # Version of the IBM product, should match offering version in repository.xml
    [System.Version] $Version
    # List of media files that make up this product
    [MediaFile[]] $MediaFiles
    # List of fixes required for the installation
    [MediaFile[]] $RequiredFixesMediaFiles
    # List of other products that this product depends on as part of the installation
    [IBMProductMedia[]] $RequiredProducts
    
    <#
    Extracts all the required media for this product to be installed.
    #>
    [Bool] ExtractMedia([String] $TargetPath, [String] $SourcePath, [System.Management.Automation.PSCredential] $SourcePathCredential, [Bool] $CleanUp, [bool] $DeepScan = $false) {
        if (([string]::IsNullOrEmpty($SourcePath)) -or ([string]::IsNullOrEmpty($TargetPath))) {
            Write-Error "TargetPath and SourcePath are required parameters"
            Return $false
        }
        #Make sure media is available, map to random drive if network drive
        $networkShare = $false
        try {
            if (($SourcePath.StartsWith("\\")) -and (!(Test-Path($SourcePath)))) {
                $networkShare = $true
            }
        } catch [System.UnauthorizedAccessException] {
            $networkShare = $true
        }

        if ($networkShare) {
            Write-Verbose "Network Share detected, need to map"
            Set-NetUse -SharePath (Split-Path($SourcePath)) -SharePathCredential $SourcePathCredential -Ensure "Present" | Out-Null
        }
        if (!(Test-Path $SourcePath -PathType Container)) {
            Write-Error "Invalid SourcePath (Not A Folder).  SourcePath should be a folder where the IBM media is residing"
        }
        if (($CleanUp) -and (Test-Path($TargetPath))) {
            Write-Verbose "Cleaning up existing target path for installation media: $TargetPath"
            Remove-Item $TargetPath -Recurse -Force
        }
        if (!(Test-Path($TargetPath))) {
            New-Item -ItemType directory -Path $TargetPath | Out-Null
        }

        try {
            $this._ExtractMedia($this, $TargetPath, $SourcePath, $DeepScan)
        } catch {
            $ErrorMessage = $_.Exception.Message
            Write-Error "An error occurred while extracting the media: $SourcePath \n Error Message: $ErrorMessage"
        } finally {
            if ($networkShare) {
                try {
                    Set-NetUse -SharePath (Split-Path($SourcePath)) -SharePathCredential $SourcePathCredential -Ensure "Absent" | Out-Null
                } catch {
                    Write-Warning "Unable to disconnect share: $SourcePath"
                }
            }
        }
        
        Return ($this._GetRepositoryLocations($this, $TargetPath, $CleanUp))
    }

    hidden [Bool] _ExtractMedia([IBMProductMedia] $ibmProductMedia, [String] $TargetPath, [String] $SourcePath, [bool] $DeepScan) {
        [Bool] $extracted = $false
        [Bool] $hasMedia = $false
        [Bool] $mediaExtracted = $false
        [Bool] $hasFixes = $false
        [Bool] $fixesExtracted = $false
        [String[]] $productTargetPath = $TargetPath
        if ($ibmProductMedia.ShortName) {
            $productTargetPath = Join-Path -Path $TargetPath -ChildPath $ibmProductMedia.ShortName
        }
        if ($ibmProductMedia.MediaFiles -and ($ibmProductMedia.MediaFiles.Count -gt 0)) {
            $hasMedia = $true
            $mediaExtracted = $true
            Foreach ($mediaFile in $ibmProductMedia.MediaFiles) {
                if ($mediaExtracted) {
                    $mediaExtracted = $mediaFile.ExtractMedia($productTargetPath, $SourcePath, $DeepScan)
                }
            }
            $extracted = $mediaExtracted
        }
        if (!$extracted -or ($hasMedia -and $mediaExtracted)) {
            if ($ibmProductMedia.RequiredFixesMediaFiles -and ($ibmProductMedia.RequiredFixesMediaFiles.Count -gt 0)) {
                $hasFixes = $true
                $fixesExtracted = $true
                Foreach ($mediaFile in $ibmProductMedia.RequiredFixesMediaFiles) {
                    if ($fixesExtracted) {
                        $fixesExtracted = $mediaFile.ExtractMedia($productTargetPath, $SourcePath, $DeepScan)
                    }
                }
                $extracted = $fixesExtracted
            }
        }
        if (!$extracted -or (($hasFixes -or $hasMedia) -and $extracted)) {
            if ($ibmProductMedia.RequiredProducts -and ($ibmProductMedia.RequiredProducts.Count -gt 0)) {
                Foreach ($ibmProduct in $ibmProductMedia.RequiredProducts) {
                    $extracted = $this._ExtractMedia($ibmProduct, $TargetPath, $SourcePath, $DeepScan)
                }
            }
        }
        Return $extracted
    }

    <#
    Returns a list of paths to the repository locations of this product and its dependent products
    #>
    [String[]] GetRepositoryLocations([String] $BasePath, [Bool] $Validate) {
        Return ($this._GetRepositoryLocations($this, $BasePath, $Validate))
    }

    hidden [String[]] _GetRepositoryLocations([IBMProductMedia] $ibmProductMedia, [String] $BasePath, [Bool] $Validate) {
        [String[]] $repositories = @();
        [String[]] $productBasePath = $BasePath
        if ($ibmProductMedia.ShortName) {
            $productBasePath = Join-Path -Path $BasePath -ChildPath $ibmProductMedia.ShortName
        }
        if ($ibmProductMedia.MediaFiles -and ($ibmProductMedia.MediaFiles.Count -gt 0)) {
            Foreach ($mediaFile in $ibmProductMedia.MediaFiles) {
                $repositories += $mediaFile.GetRepositoryLocations($productBasePath, $Validate)
            }
        }
        if ($ibmProductMedia.RequiredFixesMediaFiles -and ($ibmProductMedia.RequiredFixesMediaFiles.Count -gt 0)) {
            Foreach ($mediaFile in $ibmProductMedia.RequiredFixesMediaFiles) {
                $repositories += $mediaFile.GetRepositoryLocations($productBasePath, $Validate)
            }
        }
        if ($ibmProductMedia.RequiredProducts -and ($ibmProductMedia.RequiredProducts.Count -gt 0)) {
            Foreach ($ibmProduct in $ibmProductMedia.RequiredProducts) {
                $repositories += $this._GetRepositoryLocations($ibmProduct, $BasePath, $Validate)
            }
        }
        Return $repositories
    }

    <#
    Returns the estimated disk space that this product will consume once extracted
    #>
    [Long] GetTotalSizeOnDisk() {
        Return ($this._GetTotalSizeOnDisk($this))
    }
    
    hidden [Long] _GetTotalSizeOnDisk([IBMProductMedia] $ibmProductMedia) {
        [Long] $sizeOnDisk = 0;
        if ($ibmProductMedia.MediaFiles -and ($ibmProductMedia.MediaFiles.Count -gt 0)) {
            Foreach ($mediaFile in $ibmProductMedia.MediaFiles) {
                $sizeOnDisk += $mediaFile.SizeOnDisk
            }
        }
        if ($ibmProductMedia.RequiredFixesMediaFiles -and ($ibmProductMedia.RequiredFixesMediaFiles.Count -gt 0)) {
            Foreach ($mediaFile in $ibmProductMedia.RequiredFixesMediaFiles) {
                $sizeOnDisk += $mediaFile.SizeOnDisk
            }
        }
        if ($ibmProductMedia.RequiredProducts -and ($ibmProductMedia.RequiredProducts.Count -gt 0)) {
            Foreach ($ibmProduct in $ibmProductMedia.RequiredProducts) {
                $sizeOnDisk += $this._GetTotalSizeOnDisk($ibmProduct)
            }
        }
        Return $sizeOnDisk
    }
}