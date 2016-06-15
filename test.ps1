$resourceNamePrefix ="sudiodsa"
$resourceGroupName = $resourceNamePrefix + "rscgrp"
$VMNamePrefix = $resourceNamePrefix + "arm"
$location="East US"
$TMextensionname="TrendMicroDSA"
$TMPublisher="TrendMicro"
$dsaExtVersion="9.6"
$jsonPublic = "{}"
$jsonPrivate="{}"
$numberOfVM=50
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
        
    #Set-AzureRMVMExtension -ResourceGroupName $resourceGroupName -Location $location -VMName $vmName -Name $name -Publisher $publisher -ExtensionType $extensionType -TypeHandlerVersion $typeHandlerVersion -SettingString $settingString -ProtectedSettingString $protectedSettingString
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
    sleep 1

}
    
$jobs | ForEach {
    $_.powershell.EndInvoke($_.handle)
    $_.PowerShell.Dispose()
}

$jobs.clear()