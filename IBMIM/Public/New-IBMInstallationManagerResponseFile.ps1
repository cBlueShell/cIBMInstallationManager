##############################################################################################################
# New-IBMInstallationManagerResponseFile
#   Generates a new response file based on the template specified.
#      - Updates the repository locations from the ProductMedia parameter along with the extracted media folder
#      - Updates variables in response file from the Variables hashtable
#      - Converts credential variables to hashed passwords
##############################################################################################################
Function New-IBMInstallationManagerResponseFile {
    [CmdletBinding(SupportsShouldProcess=$True,ConfirmImpact="Low")]
    [OutputType([Boolean])]
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
    
    PROCESS {
        if ($PSCmdLet.ShouldProcess($Path)) {
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
    }
}