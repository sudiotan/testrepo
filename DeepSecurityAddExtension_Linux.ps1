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

#region List all available extensions version by location
echo ("{0} List all available extensions" -f $(Get-Date ).ToString())

$TMPublisher = "TrendMicro.DeepSecurity"
$TMextensionname = "TrendMicroDSALinux"
$dsaExtLocationVersionTable = @{}
$vmList | Select-Object -Property location -Unique | foreach {
    try {
        $dsaExtVersion = "9.6"  # default extension version
        $dsaExtVersionImages = Get-AzureRmVMExtensionImage -Location $_.location –PublisherName $TMPublisher -Type $TMextensionname -ErrorAction Stop
        
        $ver = $dsaExtVersion

        if($dsaExtVersionImages -is [Object[]]) {
            $ver = $dsaExtVersionImages[$dsaExtVersionImages.Length-1].Version
        }elseif($dsaExtVersionImages -is [Object]) {
            $ver = $dsaExtVersionImages.Version
        }
        if( $ver -match "(\d+\.\d+)\.*") {  # get first two version-number (eg : get A.B from A.B.C.D)
            $dsaExtVersion = $Matches[1]
        }

        $dsaExtLocationVersionTable.($_.location) = $dsaExtVersion

    }catch {
        throw "Error while query for all available extensions : " + $_
    }    
}

# show versions
$dsaExtLocationVersionTable | Format-Table

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
      
    Set-AzureRMVMExtension -ResourceGroupName $resourceGroupName -Location $location -VMName $vmName -Name $name -Publisher $publisher -ExtensionType $extensionType -TypeHandlerVersion $typeHandlerVersion -SettingString $settingString -ProtectedSettingString $protectedSettingString
    echo ("{0} Thread:{1} Finished adding extension for VM:{2}; ResourceGroup:{3}; Extension:{4}; Version:{5}; Location:{6}" -f $(Get-Date ).ToString(), $ThreadID, $vmName, $resourceGroupName, $name, $typeHandlerVersion, $location)
}

echo ("{0} Adding VM Extension." -f $(Get-Date ).ToString())

#for($i = 0; $i -lt $numberOfVM ; $i++){

$vmList | ForEach {
    $VMName = $_.vm_name
    $resourceGroupName = $_.resource_group
    $location = $_.location
    $version = $dsaExtLocationVersionTable[$location]
    $Parameters = @{
                    resourceGroupName=$resourceGroupName
                    location=$location
                    vmName=$VMName
                    name=$TMextensionname
                    publisher=$TMPublisher
                    extensionType=$TMextensionname
                    typeHandlerVersion=$version
                    settingString=$publicFileContent
                    protectedSettingString=$protectedFileContent
                    }
        
    $PowerShell = [powershell]::Create() 
    $PowerShell.RunspacePool = $RunspacePool
        
    echo ("{0} Adding extension for VM:{1}; ResourceGroup:{2}; Location:{3}; Version:{4}" -f $(Get-Date ).ToString(), $VMName, $_.resource_group, $location, $version)

    [void]$PowerShell.AddScript($scriptBlock)
    [void]$PowerShell.AddParameters($Parameters)
    $Handle = $PowerShell.BeginInvoke()

    $temp = "" | Select PowerShell,Handle
    $temp.PowerShell = $PowerShell
    $temp.handle = $Handle
    [void]$jobs.Add($temp)

    sleep 2
}
    
$jobs | ForEach {
    $_.powershell.EndInvoke($_.handle)
    $_.PowerShell.Dispose()
}

$jobs.clear()

#endregion 