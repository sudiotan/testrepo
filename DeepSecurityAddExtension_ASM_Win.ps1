[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)][string]$protectedFileName,
    [Parameter(Mandatory=$true)][string]$publicFileName,
    [Parameter(Mandatory=$true)][string]$vmListFileName
)

if([string]::IsNullOrWhiteSpace($protectedFileName) -or [string]::IsNullOrWhiteSpace($publicFileName) -or [string]::IsNullOrWhiteSpace($vmListFileName)) {
    throw "Please provide mandatory parameters"
}

try {
    $protectedFileContent = Get-Content -Raw -LiteralPath $protectedFileName -Encoding UTF8 -ErrorAction Stop
    $publicFileContent = Get-Content -Raw -LiteralPath $publicFileName -Encoding UTF8 -ErrorAction Stop
    $vmListFileContent = Get-Content -Raw -LiteralPath $vmListFileName -Encoding UTF8 -ErrorAction Stop
} catch {
    throw "Error while reading configuration files : " + $_
}

try {
    [void] (ConvertFrom-JSON -InputObject $protectedFileContent -ErrorAction Stop)
    [void] (ConvertFrom-JSON -InputObject $publicFileContent -ErrorAction Stop)
    $vmList = ConvertFrom-JSON -InputObject $vmListFileContent -ErrorAction Stop

    # if not array, wrap in array
    if($vmList -isnot [array]) { $vmList = @($vmList) }
} catch {
    throw "Configuration files not a valid JSON format : " + $_
}


$location = "East US"
$AzureAccount = "twdsauto@dsauto.onmicrosoft.com"
$AzurePassword = '2010@Azure!@#'
$securePassword = ConvertTo-SecureString -AsPlainText -Force $AzurePassword
$AzureSubscriptionID = "dabc1645-8ed8-4f30-a200-0c1c55b33657"
$vmStorageAccountName = "sudioasmstorageact"

echo ("{0} Login into Azure" -f $(Get-Date ).ToString())
$cred = New-Object System.Management.Automation.PSCredential $AzureAccount, $securePassword
add-AzureAccount -Credential $cred
Select-AzureSubscription -SubscriptionId $AzureSubscriptionID -Default
Set-AzureSubscription -SubscriptionId $AzureSubscriptionID -CurrentStorageAccountName $vmStorageAccountName

#region Get available extensions version
echo ("{0} Get available extensions" -f $(Get-Date ).ToString())

$TMPublisher = "TrendMicro.DeepSecurity"
$TMextensionname = "TrendMicroDSA"

$dsaExtVersion = (Get-AzureVMAvailableExtension -ExtensionName $TMextensionname –Publisher $TMPublisher).Version

#endregion 


#region Add extensions for every VMs

$minThreadCount = 1
$maxThreadCount = 100
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
    
    $exvm7 = Get-AzureVM -ServiceName $vmName -Name $vmName
    $exvm7 |fl

    Set-AzureVMExtension -VM $exvm7 -Version $typeHandlerVersion -ExtensionName $extensionType -Publisher $publisher -PrivateConfiguration $protectedSettingString -PublicConfiguration $settingString | Update-AzureVM
    
    echo ("{0} Thread:{1} Finished adding extension for VM:{2}; ResourceGroup:{3}; Extension:{4}; Version:{5}; Location:{6}" -f $(Get-Date ).ToString(), $ThreadID, $vmName, $resourceGroupName, $name, $typeHandlerVersion, $location)
}

echo ("{0} Adding VM Extension." -f $(Get-Date ).ToString())

#for($i = 0; $i -lt $numberOfVM ; $i++){

$vmList | ForEach {
    $VMName = $_.vm_name
    $resourceGroupName = $_.resource_group
    $location = $_.location
    $Parameters = @{
                    resourceGroupName=$resourceGroupName
                    location=$location
                    vmName=$VMName
                    name=$TMextensionname
                    publisher=$TMPublisher
                    extensionType=$TMextensionname
                    typeHandlerVersion=$dsaExtVersion
                    settingString=$publicFileContent
                    protectedSettingString=$protectedFileContent
                    }
        
    $PowerShell = [powershell]::Create() 
    $PowerShell.RunspacePool = $RunspacePool
        
    echo ("{0} Adding extension for VM:{1}; ResourceGroup:{2}; Location:{3}; Version:{4}" -f $(Get-Date ).ToString(), $VMName, $_.resource_group, $location, $dsaExtVersion)

    $PowerShell.AddScript($scriptBlock)
    $PowerShell.AddParameters($Parameters)
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

#endregion 