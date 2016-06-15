Remove-Variable * -ErrorAction SilentlyContinue
$DebugPreference = "Continue"
###################################### Azure Login  ######################################

$location = "East US"
$AzureAccount = "twdsauto@dsauto.onmicrosoft.com"
$AzurePassword = '2010@Azure!@#'
$securePassword = ConvertTo-SecureString -AsPlainText -Force $AzurePassword
$AzureSubscriptionID = "dabc1645-8ed8-4f30-a200-0c1c55b33657"

echo ("{0} Login into Azure" -f $(Get-Date ).ToString())
$credential = New-Object System.Management.Automation.PSCredential $AzureAccount, $securePassword
Login-AzureRmAccount -Credential $credential
Select-AzureRmSubscription -SubscriptionId $AzureSubscriptionID

###################################### Create Node  ######################################

# Assign common values
$numberOfVM = 10
$createVM = "Yes"
$addExtension = "Yes"
$VMPlatform = "windows"

# vm information
$resourceNamePrefix ="sudiodsa"
$resourceGroupName = $resourceNamePrefix + "rscgrp"
$VMNamePrefix = $resourceNamePrefix + "arm"
$deployName = $resourceNamePrefix + "deploy" + ([guid]::NewGuid().ToString()).substring(0,4)
$templateURI = 'https://raw.githubusercontent.com/sudiotan/testrepo/master/azuredeploy_multi_VM_sudio.json'  # VM template in JSON
$params = @{vmName=$VMNamePrefix;numberOfInstances=$numberOfVM}

# tenant information
$tenatid = "4DF6D6D1-3467-AA26-0DD8-1BAC774D4930"
$tenantPassword = "96287CF6-F06B-0416-1903-9C982617F7DA"
$DSMname = "dev-agents.deepsecurity.trendmicro.com"
$DSMport = "443"
$policyNameorID = ""
$tenantFileName = "private.config"
$dsmFileName = "public.config"


#region List All Available DeepSecurity Extension

# DSA extension information
# -Publisher LocalTest.TrendMicro.DeepSecurity  local build
# -Publisher Test.TrendMicro.DeepSecurity     test publisher (staging)
# -Publisher TrendMicro.DeepSecurity           official publisher
$TMPublisher = "TrendMicro.DeepSecurity"
$TMwinextensionname = "TrendMicroDSA"
$TMlinuxextensionname = "TrendMicroDSALinux"

if ($VMPlatform -eq "windows" ) {
$TMextensionname = $TMwinextensionname
}else {
$TMextensionname = $TMlinuxextensionname
}

echo ("{0} List all available extensions" -f $(Get-Date ).ToString())
$dsaExtVersion = "9.6"  # default extension version
# list all available extensions, 
$dsaExtVersionImages = Get-AzureRmVMExtensionImage -Location $location –PublisherName $TMPublisher -Type $TMextensionname
echo($dsaExtVersionImages)
$ver = $dsaExtVersion

if($dsaExtVersionImages -is [Object[]]) {
    $ver = $dsaExtVersionImages[$dsaExtVersionImages.Length-1].Version
}elseif($dsaExtVersionImages -is [Object]) {
    $ver = $dsaExtVersionImages.Version
}
if( $ver -match "(\d+\.\d+)\.*") {  # get first two version-number (eg : get A.B from A.B.C.D)
    $dsaExtVersion = $Matches[1]
}
#endregion 

#region Create VM Using Deployment Template
if ($createVM -eq "Yes" ) {
	echo ("{0} Creating resource group : {1}" -f $(Get-Date ).ToString(), $resourceGroupName)
	New-AzureRmResourceGroup -Name $resourceGroupName -Location $location

	echo ("{0} Deploying Resources using template:{1}; ResourceGroup:{2}; deployName:{3}" -f $(Get-Date ).ToString(), $templateURI, $resourceGroupName, $deployName)
	New-AzureRmResourceGroupDeployment -Name $deployName -ResourceGroupName $resourceGroupName -TemplateUri $templateURI -TemplateParameterObject $params
	echo ("{0} Finished deploying template:{1}" -f $(Get-Date ).ToString(), $templateURI)

}
#endregion


#region Add VM Extension
$minThreadCount = 1
$maxThreadCount = 100
if ($addExtension -eq "Yes" ) {

    echo "{
    'tenantID': '$tenatid' ,
    'tenantPassword':'$tenantPassword'
    }" > $tenantFileName
    echo "{
    'DSMname': '$DSMname',
    'DSMport':'$DSMport',
    'policyID':'$policyNameorID'
    }" > $dsmFileName

    echo ("{0} Reading from config file." -f $(Get-Date ).ToString())
    $jsonPrivate = Get-Content -Raw -Path $tenantFileName
    $jsonPublic = Get-Content -Raw -Path $dsmFileName

    # multithread with runspace
    echo ("{0} Creating runspace." -f $(Get-Date ).ToString())
    $SessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    $RunspacePool = [runspacefactory]::CreateRunspacePool($minThreadCount, $maxThreadCount)
    $RunspacePool.Open()
    $jobs = New-Object System.Collections.ArrayList
    $scriptBlock = {
        Param (
            $resourceGroupName,
            $location,
            $vmName,
            $name,
            $publisher,
            $extensionType,
            $typeHandlerVersion,
            $settingString,
            $protectedSettingString
        )
            
        $ThreadID = [appdomain]::GetCurrentThreadId()
        
        Set-AzureRMVMExtension -ResourceGroupName $resourceGroupName -Location $location -VMName $vmName -Name $name -Publisher $publisher -ExtensionType $extensionType -TypeHandlerVersion $typeHandlerVersion -SettingString $settingString -ProtectedSettingString $protectedSettingString
        echo ("{0} Thread:{1} Finished adding extension for VM:{2}; ResourceGroup:{3}; Extension:{4}; Version:{5}" -f $(Get-Date ).ToString(), $ThreadID, $vmName, $resourceGroupName, $name, $typeHandlerVersion)
    }

    echo ("{0} Adding VM Extension." -f $(Get-Date ).ToString())

    for($i = 0; $i -lt $numberOfVM ; $i++){
        $VMName = $VMNamePrefix + $i 
        $Parameters = @{
                        resourceGroupName=$resourceGroupName
                        location=$location
                        vmName=$VMName
                        name=$TMextensionname
                        publisher=$TMPublisher
                        extensionType=$TMextensionname
                        typeHandlerVersion=$dsaExtVersion
                        settingString=$jsonPublic
                        protectedSettingString=$jsonPrivate
                        }
        
        $PowerShell = [powershell]::Create() 
        $PowerShell.RunspacePool = $RunspacePool
        
        echo ("{0} Adding extension for VM:{1}" -f $(Get-Date ).ToString(), $VMName)

        [void]$PowerShell.AddScript($scriptBlock)
        [void]$PowerShell.AddParameters($Parameters)
        $Handle = $PowerShell.BeginInvoke()

        $temp = "" | Select PowerShell,Handle
        $temp.PowerShell = $PowerShell
        $temp.handle = $Handle
        [void]$jobs.Add($temp)
        sleep 4

    }
    
    $jobs | ForEach {
        $_.powershell.EndInvoke($_.handle)
        $_.PowerShell.Dispose()
    }

    $jobs.clear()
}
#endregion