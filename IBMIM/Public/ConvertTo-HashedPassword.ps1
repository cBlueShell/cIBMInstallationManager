##############################################################################################################
# ConvertTo-HashedPassword
#   Generates a hashed password from password specified using the IBM Installation Manager Command Line
##############################################################################################################
Function ConvertTo-HashedPassword() {
    [CmdletBinding(SupportsShouldProcess=$False)]
    [OutputType([String])]
    Param (
        [Parameter(Mandatory=$True, Position=0)]
        [System.Management.Automation.PSCredential]
        $UserCredential
    )

    [String] $hashedPwd = $null
    Write-Verbose "ConvertTo-HashedPassword called"

    $iimHome = Get-IBMInstallationManagerHome
    if ($iimHome) {
        $iimcPath = Join-Path -Path $iimHome -ChildPath "eclipse\IBMIMc.exe"
        if (Test-Path($iimcPath)) {
            $plainpwd = $UserCredential.GetNetworkCredential().Password
            [String[]] $imArgs = @('-noSplash','-silent','encryptstring','"' + $plainpwd + '"')

            $imcl = Invoke-ProcessHelper $iimcPath $imArgs
            if ($imcl -and ($imcl.ExitCode -eq 0)) {
                $hashedPwd = $imcl.StdOut
                if ($hashedPwd) {
                    Write-Verbose "ConvertTo-HashedPassword returning hashed password $hashedPwd"
                } else {
                    Write-Error "ConvertTo-HashedPassword did not return anything"
                }
            } else {
                $errorMsg = (&{if($imcl) {$imcl.StdOut} else {$null}})
                Write-Error "An error occurred while generating the hashed passwordr: $errorMsg"
            }
        } else {
            Write-Error "Unable to find path to the IBM Installation Manager Cmd Line: $iimcPath"
        }
    } else {
        Write-Error "Unable to find IBM Installation Manager: $iimHome"
    }

    Return $hashedPwd
}