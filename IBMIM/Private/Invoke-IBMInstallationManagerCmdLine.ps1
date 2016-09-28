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