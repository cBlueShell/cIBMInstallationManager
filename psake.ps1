# PSake makes variables declared here available in other scriptblocks
# Init some things
Properties {
    # Find the build folder based on build system
    $ProjectRoot = $ENV:BHProjectPath
    if (-not $ProjectRoot) {
        $ProjectRoot = $PSScriptRoot
    }

    $Timestamp = Get-date -uformat "%Y%m%d-%H%M%S"
    $PSVersion = $PSVersionTable.PSVersion.Major
    $TestFile = "TestResults_PS$PSVersion`_$TimeStamp.xml"
    $lines = '----------------------------------------------------------------------'

    # List of the PowerShell scripts to test
    $filesToTest = Get-ChildItem *.psm1,*.psd1,*.ps1 -Recurse -Exclude *build.ps1,*.pester.ps1,*Tests.ps1,*psake.ps1,*.psdeploy.ps1

    $Verbose = @{}
    if($ENV:BHCommitMessage -match "!verbose") {
        $Verbose = @{Verbose = $True}
    }
}

Task Default -depends Init, Analyze, Test, Build, Deploy

Task Init {
    $lines
    Set-Location $ProjectRoot
    "Build System Details:"
    Get-Item ENV:BH*
    "`n"
}

Task Analyze {
    $lines
    ForEach ($testPath in $filesToTest) {
        try {
            Write-Output "Running ScriptAnalyzer on $($testPath)"

            if ($env:APPVEYOR) {
                Add-AppveyorTest -Name "PsScriptAnalyzer" -Outcome Running
                $timer = [System.Diagnostics.Stopwatch]::StartNew()
            }

            $saResults = Invoke-ScriptAnalyzer -Path $testPath -Verbose:$false
            if ($saResults) {
                $saResults | Format-Table
                $saResultsString = $saResults | Out-String
                if ($saResults.Severity -contains 'Error' -or $saResults.Severity -contains 'Warning') {
                    if ($env:APPVEYOR) {
                        Add-AppveyorMessage -Message "PSScriptAnalyzer output contained one or more result(s) with 'Error or Warning' severity.`
                        Check the 'Tests' tab of this build for more details." -Category Error
                        Update-AppveyorTest -Name "PsScriptAnalyzer" -Outcome Failed -ErrorMessage $saResultsString                  
                    }
                    Write-Error -Message "One or more Script Analyzer errors/warnings where found in $($testPath). Build cannot continue!"  
                } else {
                    Write-Output "All ScriptAnalyzer tests passed"
                    if ($env:APPVEYOR) {
                        Update-AppveyorTest -Name "PsScriptAnalyzer" -Outcome Passed -StdOut $saResultsString -Duration $timer.ElapsedMilliseconds
                    }
                }
            }
        } catch {
            $ErrorMessage = $_.Exception.Message
            $FailedItem = $_.Exception.ItemName
            Write-Output $ErrorMessage
            Write-Output $FailedItem
            Write-Error "The build failed when working with $($testPath)."
        }
    }
    "`n"
}

Task Test -Depends Init, Analyze {
    $lines
    "`n`tSTATUS: Testing with PowerShell $PSVersion"

    # Gather test results. Store them in a variable and file
    $TestResults = Invoke-Pester -Path $ProjectRoot\Tests -PassThru -OutputFormat NUnitXml -OutputFile "$ProjectRoot\$TestFile"

    # In Appveyor?  Upload our tests! #Abstract this into a function?
    If($ENV:BHBuildSystem -eq 'AppVeyor') {
        (New-Object 'System.Net.WebClient').UploadFile(
            "https://ci.appveyor.com/api/testresults/nunit/$($env:APPVEYOR_JOB_ID)",
            "$ProjectRoot\$TestFile" )
    }

    Remove-Item "$ProjectRoot\$TestFile" -Force -ErrorAction SilentlyContinue

    # Failed tests?
    # Need to tell psake or it will proceed to the deployment. Danger!
    if($TestResults.FailedCount -gt 0) {
        Write-Error "Failed '$($TestResults.FailedCount)' tests, build failed"
    }
    "`n"
}

Task Build -Depends Test {
    $lines
    
    # Load the module, read the exported functions, update the psd1 FunctionsToExport
    Set-ModuleFunctions @Verbose

    # Bump the module version
    $Version = Get-NextPSGalleryVersion -Name $env:BHProjectName
    Write-Output "Setting Version: $Version"
    Update-Metadata -Path $env:BHPSModuleManifest -PropertyName ModuleVersion -Value $Version

    "`n"
}

Task Deploy -Depends Build {
    $lines

    # Deploy to PS Gallery
    $Params = @{
        Path = $ProjectRoot
        Force = $true
        Recurse = $false # We keep psdeploy artifacts, avoid deploying those : )
    }
    Invoke-PSDeploy @Verbose @Params

    # Create a clean to build the artifact
    $artifactDir = "$PSScriptRoot\Artifact"
    if (Test-Path $artifactDir) {
        Remove-Item $artifactDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -Path $artifactDir -ItemType Directory -Force

    # Copy the correct items into the artifacts directory, filtering out the junk
    Start-Process -FilePath 'robocopy.exe' -ArgumentList "`"$($PSScriptRoot)`" `"$($PSScriptRoot)\Artifact\cIBMInstallationManager`" /S /R:1 /W:1 /XD Artifact .kitchen .git /XF .gitignore build.ps1 psake.ps1 *.yml *.xml" -Wait -NoNewWindow

    # Create a zip file artifact
    Compress-Archive -Path $PSScriptRoot\Artifact\cIBMInstallationManager -DestinationPath $PSScriptRoot\Artifact\cIBMInstallationManager-$build_version.zip -Force

    if ($env:APPVEYOR) {
        # Push the artifact into appveyor
        $zip = Get-ChildItem -Path $PSScriptRoot\Artifact\*.zip |  % { Push-AppveyorArtifact $_.FullName -FileName $_.Name }
    }

    "`n"
}