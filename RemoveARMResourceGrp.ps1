[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)][string]$rscGrpListFileName,
    [Parameter(Mandatory=$true)][string]$configFileName
)

if([string]::IsNullOrWhiteSpace($rscGrpListFileName) -or [string]::IsNullOrWhiteSpace($configFileName)) {
    throw "Please provide mandatory parameters"
}

try {
    $rscGrpListStr = Get-Content -Raw -LiteralPath $rscGrpListFileName -Encoding UTF8 -ErrorAction Stop
    $configFileStr = Get-Content -Raw -LiteralPath $configFileName -Encoding UTF8 -ErrorAction Stop
} catch {
    throw "Error while reading configuration files : " + $_
}

try {
    $rscGrpList = ConvertFrom-JSON -InputObject $rscGrpListStr -ErrorAction Stop
    $configurations = ConvertFrom-JSON -InputObject $configFileStr -ErrorAction Stop

    # if not array, wrap in array
    if($rscGrpList -isnot [array]) { $rscGrpList = @($rscGrpList) }
} catch {
    throw "Configuration files not a valid JSON format : " + $_
}


#region Login into Azure

$securePassword = ConvertTo-SecureString -AsPlainText -Force $configurations.azurePassword
echo ("{0} Login into Azure" -f $(Get-Date ).ToString())
$credential = New-Object System.Management.Automation.PSCredential $configurations.azureAccount, $securePassword
Login-AzureRmAccount -Credential $credential
Select-AzureRmSubscription -SubscriptionId $configurations.azureSubscriptionID

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
        $resourceGroupName
    )
            
    $ThreadID = [appdomain]::GetCurrentThreadId()
    fl
    
    Remove-AzureRmResourceGroup -Name $resourceGroupName -Force
    echo ("{0} Thread:{1} Finished removing ResourceGroup:{2}" -f $(Get-Date ).ToString(), $ThreadID, $resourceGroupName)
}

echo ("{0} Removing ResourceGroups." -f $(Get-Date ).ToString())


$rscGrpList | ForEach {
    $resourceGroupName = $_.resource_group
    $Parameters = @{
                    resourceGroupName=$resourceGroupName
                    }
        
    $PowerShell = [powershell]::Create() 
    $PowerShell.RunspacePool = $RunspacePool
        
    echo ("{0} Removing ResourceGroup:{1}" -f $(Get-Date ).ToString(), $resourceGroupName)

    $PowerShell.AddScript($scriptBlock)
    $PowerShell.AddParameters($Parameters)
    $Handle = $PowerShell.BeginInvoke()

    $temp = "" | Select PowerShell,Handle
    $temp.PowerShell = $PowerShell
    $temp.handle = $Handle
    [void]$jobs.Add($temp)

    sleep 2
}
    
$jobs | ForEach {
    $_.powershell.EndInvoke($_.handle)
	
	if ($_.powershell -and $_.powershell.Streams) {

        foreach ($errorRecord in $_.powershell.Streams.Error) {
            $errorRecord
        }

        foreach ($warningRecord in $_.powershell.Streams.Warning) {
            $warningRecord
        }

        foreach ($verboseRecord in $_.powershell.Streams.Verbose) {
            $verboseRecord
        }

        foreach ($debugRecord in $_.powershell.Streams.Debug) {
            $debugRecord
        }
        
    }
	
    $_.PowerShell.Dispose()
}

$jobs.clear()

#endregion 