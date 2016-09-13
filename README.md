#cIBMInstallationManager

PowerShell CmdLets and Class-Based DSC resources to manage IBM Installation Manager on Windows Environments.

To get started using this module just type the command below and the module will be downloaded from [PowerShell Gallery](https://www.powershellgallery.com/packages/cIBMInstallationManager/)
```shell
PS> Install-Module -Name cIBMInstallationManager
```

## Resources

* **cIBMInstallationManager** installs IBM Installation Manager on target machine.

### cIBMInstallationManager

* **Ensure**: (Required) Ensures that IBM Installation Manager is Present or Absent on the machine.
* **Version**: (Key) The version of IBM Installation Manager to install/update.
* **InstallationDirectory**: Installation path.  Default: C:\IBM\InstallationManager.
* **SourcePath**: UNC or local file path to the zip file needed for the installation.
* **SourcePathCredential**: Credential to be used to map sourcepath if a remote share is being specified.
* **TempDir**: Overrides default Temp Folder used by IBM Installation Manager. Useful when Antivirus monitors the default folders and lock onto the temp files.  

## Depedencies
[7-Zip](http://www.7-zip.org/ "7-Zip") needs to be installed on the target machine.  You can add 7-Zip to your DSC configuration by using the Package
DSC Resource or by leveraging the [x7Zip DSC Module](https://www.powershellgallery.com/packages/x7Zip/ "x7Zip at PowerShell Gallery")

## Versions

### 1.0.5/1.0.6
* Minor fixes

### 1.0.4

* Added command-line based single product installation support (ideal for fixes, cumulative fixes, fixpacks, etc)
* Added Get-IBMTempDir cmdlet that retrieves directory used by IIM or falls back to the user's/system's temp folder
* Fixed issue with module loading and temporary directory handling
* New CmdLets: **Install-IBMProductViaCmdLine**, **Invoke-IBMInstallationManagerCmdLine**, **Get-IBMTempDir**


### 1.0.3

* Added TempDir support/DSC property
* New CmdLets: **Set-JavaProperties**, **Get-JavaProperties**, **Set-IBMInstallationManagerTempDir**, **Get-IBMInstallationManagerTempDir**

### 1.0.2

* Adds classes for modeling IBM product media
* Adds support for Response File-Based installations
* New CmdLets: **Install-IBMProduct**, **Install-IBMProductViaResponseFile**, **New-IBMInstallationManagerResponseFile**, **Invoke-ProcessHelper** 
* Removed CmdLets: **Expand-IBMInstallationMedia** _Refactored into the new IBMProductMedia PowerShell Class

### 1.0.0

* Initial release with the following resources 
    - cIBMInstallationManager

## Examples

### Install IBM Installation Manager

This configuration will install [7-Zip](http://www.7-zip.org/ "7-Zip") using the DSC Package Resource and install
IBM Installation Manager version 1.8.3 onto the C:\IBM\IIM directory

Note: This requires the following DSC modules:
* xPsDesiredStateConfiguration

```powershell
Configuration IIM
{
    Import-DSCResource -module cIBMInstallationManager
    Package SevenZip {
        Ensure = 'Present'
        Name = '7-Zip 9.20 (x64 edition)'
        ProductId = '23170F69-40C1-2702-0920-000001000000'
        Path = 'C:\Media\7z920-x64.msi'
    }
    cIBMInstallationManager iimInstall
    {
        Ensure = 'Present'
        InstallationDirectory = 'C:\IBM\IIM'
        Version = '1.8.3'
        SourcePath = 'C:\Media\agent.installer.win32.win32.x86_1.8.3000.20150606_0047.zip'
        DependsOn= "[Package]SevenZip"
    }
}
IIM
Start-DscConfiguration -Wait -Force -Verbose IIM
```