#requires -Version 5

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
        Version = '1.8.4.1'
        SourcePath = 'C:\Media\IBM\InstallationManager\agent.installer.win32.win32.x86_64_1.8.4001.20160217_1716.zip'
        DependsOn= "[Package]SevenZip"
    }
}
IIM
Start-DscConfiguration -Wait -Force -Verbose IIM