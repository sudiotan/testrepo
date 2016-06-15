Remove-Variable * -ErrorAction SilentlyContinue
$DebugPreference = "Continue"
###################################### Azure Login  ######################################

$rglocation = "East US"
$clientacc = “twdsauto@dsauto.onmicrosoft.com"
$securePassword = ConvertTo-SecureString -AsPlainText -Force ‘2010@Azure!@#'
$accsubscription = "dabc1645-8ed8-4f30-a200-0c1c55b33657"
$sleepnumber = "60"
#$vmStorageAccountName = "mmikets155"

echo ("{0} Login into Azure" -f $(Get-Date ).ToString())
$cred = New-Object System.Management.Automation.PSCredential $clientacc, $securePassword
login-azurermaccount -Credential $cred
Select-AzureRmSubscription -SubscriptionId $accsubscription

###################################### Create Node  ######################################

# Assign common values
$vmnumber = 200
$addnode = "Yes"
$addextension = "Yes"
$addplatform = "windows"

# vm information
$vmsize = "Basic_A0"
$vmnamestart = "sudioarmdsa"
$deployName = 'sudiodp' + ([guid]::NewGuid().ToString()).substring(0,4)
$templateURI = 'https://raw.githubusercontent.com/sudiotan/testrepo/master/azuredeploy_multi_VM_sudio.json'  # VM template in JSON
$params = @{vmName=$vmnamestart;numberOfInstances=$vmnumber}

# tenant information
$tenatid = "4DF6D6D1-3467-AA26-0DD8-1BAC774D4930"
$tenantPassword = "96287CF6-F06B-0416-1903-9C982617F7DA"
$DSMname = "dev-agents.deepsecurity.trendmicro.com"
$DSMport = "443"
$policyNameorID = ""
$tenantFileName = "private.config"
$dsmFileName = "public.config"

# DSA extension information
##-Publisher LocalTest.TrendMicro.DeepSecurity  local build
##-Publisher Test.TrendMicro.DeepSecurity     test publisher (staging)
##-Publisher TrendMicro.DeepSecurity           official publisher
######記得要改 dsaExtVersion#####
$TMPublisher = "TrendMicro.DeepSecurity"
$TMwinextensionname = "TrendMicroDSA"
$TMlinuxextensionname = "TrendMicroDSALinux"

if ($addplatform -eq "windows" ) {
$TMextensionname = $TMwinextensionname
}else {
$TMextensionname = $TMlinuxextensionname
}


echo ("{0} List all available extenstions :" -f $(Get-Date ).ToString())
$dsaExtVersion = "9.6"  # default extension version
# list all available extensions, 
$dsaExtVersionImages = Get-AzureRmVMExtensionImage -Location $rglocation –PublisherName $TMPublisher -Type $TMextensionname
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
 


if ($addnode -eq "Yes" ) {
###############################################Create VM START ####################################################
echo ("{0} Creating resource group : {1}" -f $(Get-Date ).ToString(), $vmnamestart)
New-AzureRmResourceGroup -Name $vmnamestart -Location $rglocation

echo ("{0} Deploying Resources using template:{1}; ResourceGroup:{2}; deployName:{3}" -f $(Get-Date ).ToString(), $templateURI,$vmnamestart,$deployName)
New-AzureRmResourceGroupDeployment -Name $deployName -ResourceGroupName $vmnamestart -TemplateUri $templateURI -TemplateParameterObject $params
echo ("{0} Finished deploying template:{1}" -f $(Get-Date ).ToString(), $templateURI)
##############################################Create VM END #######################################################
}

############################################### Create VM Extension ####################################################

#region Add Extension
$minThreadCount = 1
$maxThreadCount = 100
if ($addextension -eq "Yes" ) {
    #sleep $sleepnumber

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
        echo ("{0} Thread:{1} Add extension for VM:{2}; ResourceGroup:{3}; Extension:{4}; Version:{5}" -f $(Get-Date ).ToString(), $ThreadID, $vmName, $resourceGroupName, $name, $typeHandlerVersion)
        Set-AzureRMVMExtension -ResourceGroupName $resourceGroupName -Location $location -VMName $vmName -Name $name -Publisher $publisher -ExtensionType $extensionType -TypeHandlerVersion $typeHandlerVersion -SettingString $settingString -ProtectedSettingString $protectedSettingString
    }

    echo ("{0} Adding VM Extension." -f $(Get-Date ).ToString())

    for($i = 0; $i -lt $vmnumber ; $i++){
        $machine7 = $vmnamestart + $i 
        $Parameters = @{
                        resourceGroupName=$vmnamestart
                        location=$rglocation
                        vmName=$machine7
                        name=$TMextensionname
                        publisher=$TMPublisher
                        extensionType=$TMextensionname
                        typeHandlerVersion=$dsaExtVersion
                        settingString=$jsonPublic
                        protectedSettingString=$jsonPrivate
                        }
        
        $PowerShell = [powershell]::Create() 
        $PowerShell.RunspacePool = $RunspacePool
        
        echo ("{0} Invoking job for VM:{1}" -f $(Get-Date ).ToString(), $machine7)

        [void]$PowerShell.AddScript($scriptBlock)
        [void]$PowerShell.AddParameters($Parameters)
        $Handle = $PowerShell.BeginInvoke()

        $temp = "" | Select PowerShell,Handle
        $temp.PowerShell = $PowerShell
        $temp.handle = $Handle
        [void]$jobs.Add($temp)
        sleep 5

    }
    
    $jobs | ForEach {
        $_.powershell.EndInvoke($_.handle)
        $_.PowerShell.Dispose()
    }

    $jobs.clear()
}
#endregion