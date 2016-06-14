Remove-Variable * -ErrorAction SilentlyContinue

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
$vmnumber = "2"
$addnode = "Yes"
$addextension = "Yes"
$addplatform = "windows"

# vm information
$vmsize = "Basic_A0"
$vmnamestart = "sudioarmdsa2"
$deployName = 'sudiodp' + ([guid]::NewGuid().ToString()).substring(0,4)
$templateURI = 'https://raw.githubusercontent.com/sudiotan/testrepo/master/azuredeploy_multi_VM_sudio.json'  # VM template in JSON
$params = @{vmName=$vmnamestart;numberOfInstances=2}

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
if ($addextension -eq "Yes" ) {
    sleep $sleepnumber

    echo "{
    'tenantID': '$tenatid' ,
    'tenantPassword':'$tenantPassword'
    }" > $tenantFileName
    echo "{
    'DSMname': '$DSMname',
    'DSMport':'$DSMport',
    'policyID':'$policyNameorID'
    }" > $dsmFileName

    $jsonPrivate = Get-Content -Raw -Path $tenantFileName
    $jsonPublic = Get-Content -Raw -Path $dsmFileName

    for($i = 0; $i -lt $vmnumber ; $i++){
        $machine7 = $vmnamestart + $i 
        echo ("{0} Add extension for VM:{1}; ResourceGroup:{2}; Extension:{3}; Version:{4}" -f $(Get-Date ).ToString(), $machine7, $vmnamestart, $TMextensionname, $dsaExtVersion)
        Set-AzureRMVMExtension -ResourceGroupName $vmnamestart -Location $rglocation -VMName $machine7 -Name $TMextensionname -Publisher $TMPublisher -ExtensionType $TMextensionname -TypeHandlerVersion $dsaExtVersion -SettingString $jsonPublic -ProtectedSettingString $jsonPrivate
    }
}
#endregion