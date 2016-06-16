 [CmdletBinding()]
 param (
    #[Parameter(Mandatory=$true)][string]$configFile,
    
    #TODO change to Mandatory
    [string]$configFileName = "config.json"
 )

try {
    $configFile = Get-Content -Raw -LiteralPath $configFileName -Encoding UTF8 -ErrorAction Stop
} catch {
    throw "Error while reading configuration files : " + $_
}

try {
    $configurations = ConvertFrom-JSON -InputObject $configFile -ErrorAction Stop
} catch {
    throw "Configuration file not a valid JSON format : " + $_
}


if([string]::IsNullOrWhiteSpace($configurations.location) `
    -or [string]::IsNullOrWhiteSpace($configurations.numberOfVM) `
    -or [string]::IsNullOrWhiteSpace($configurations.resourceNamePrefix) `
    -or [string]::IsNullOrWhiteSpace($configurations.azureAccount) `
    -or [string]::IsNullOrWhiteSpace($configurations.azurePassword) `
    -or [string]::IsNullOrWhiteSpace($configurations.azureSubscriptionID)) {
    throw "Please provide mandatory parameters"
}

#region Login into Azure

$securePassword = ConvertTo-SecureString -AsPlainText -Force $configurations.azurePassword
$AzureSubscriptionID = "dabc1645-8ed8-4f30-a200-0c1c55b33657"

echo ("{0} Login into Azure" -f $(Get-Date ).ToString())
$credential = New-Object System.Management.Automation.PSCredential $configurations.azureAccount, $securePassword
Login-AzureRmAccount -Credential $credential
Select-AzureRmSubscription -SubscriptionId $configurations.azureSubscriptionID

#endregion


#region Create VM Using Deployment Template

# vm information
$numberOfVM = $configurations.numberOfVM
$resourceNamePrefix = $configurations.resourceNamePrefix
$resourceGroupName = $resourceNamePrefix + "rscgrp"
$VMNamePrefix = $resourceNamePrefix + "arm"
$deployName = $resourceNamePrefix + "deploy" + ([guid]::NewGuid().ToString()).substring(0,4)
$templateURI = $configurations.deploymentTemplateURI

$params = @{
    vmName = $VMNamePrefix
    numberOfVM = $numberOfVM
    vmAdminUsername = $configurations.vmAdminUsername
    vmAdminPassword = $configurations.vmAdminPassword
    vmSize = $configurations.vmSize
    imagePublisher = $configurations.imagePublisher
    imageOffer = $configurations.imageOffer
    imageSku = $configurations.imageSku
    imageVersion = $configurations.imageVersion
}

echo ("{0} Creating resource group : {1}" -f $(Get-Date ).ToString(), $resourceGroupName)
New-AzureRmResourceGroup -Name $resourceGroupName -Location $configurations.location

echo ("{0} Deploying {1} resources using ResourceGroup:{2}; deployName:{3}; template:{4};" -f $(Get-Date ).ToString(), $numberOfVM, $resourceGroupName, $deployName, $templateURI)
New-AzureRmResourceGroupDeployment -Name $deployName -ResourceGroupName $resourceGroupName -TemplateUri $templateURI -TemplateParameterObject $params
echo ("{0} Finished deploying template:{1}" -f $(Get-Date ).ToString(), $templateURI)

#endregion


#region Dump created VMs to JSON file

$vmJsonArr = New-Object System.Collections.ArrayList
0..($numberOfVM - 1) | foreach {
    $vmJsonArr.add(@{resource_group =$resourceGroupName; vm_name=$VMNamePrefix + $_ ;location=$configurations.location})
}
$vmJsonArr |ConvertTo-Json |Out-File -Encoding utf8 -Force ($PSScriptRoot + "\" + "VMList.config")

#endregion