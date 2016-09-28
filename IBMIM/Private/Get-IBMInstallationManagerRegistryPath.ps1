# Global Variables / Resource Configuration
$IIM_PATH = "HKLM:\Software\IBM\Installation Manager"
$IIM_PATH_64 = "HKLM:\Software\Wow6432Node\IBM\Installation Manager"
$IIM_PATH_USER = "HKCU:\Software\IBM\Installation Manager"
$IIM_PATH_USER_64 = "HKCU:\Software\Wow6432Node\IBM\Installation Manager"

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