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