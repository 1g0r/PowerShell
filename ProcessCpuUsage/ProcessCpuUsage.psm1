﻿function Convert-ToPSObject{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true, 
                   ValueFromPipeline=$true,
                   ValueFromPipelineByPropertyName=$true, 
                   Position=0)]
        $Object
    )
    $type = $object.GetType();
    if($type.Name.Equals('PSCustomObject', [System.StringComparison]::InvariantCultureIgnoreCase)){
        $result = @{};
        $Object.psobject.properties | % {$result[$_.name] = (Convert-ToPSObject $_.value)}
        return $result;
    }
    if($type.IsArray){
        $arr = @()   
        $Object | % { $arr += Convert-ToPSObject $_ }       
        return $arr
    }
    return $Object;
}
 $wrapProcess = {
    param(
        [System.Diagnostics.Process]$proc
    )

    if(($proc |gm -Name 'PrevCPU') -eq $null){
        $proc |Add-Member 'PrevCPU' ($proc.CPU)
        $proc |Add-Member 'PrevTime' ([DateTime]::UtcNow)
    }
    return $proc
}

$getCpuUsage = {
    param([System.Diagnostics.Process]$procWrap)
    
    $delta = ($procWrap.CPU - $procWrap.PrevCPU)/(([DateTime]::UtcNow - $procWrap.PrevTime).TotalSeconds)

    if(($procWrap |gm -Name 'CPUPercent') -eq $null){
        $procWrap |Add-Member 'CPUPercent' ($delta * 100 /$env:NUMBER_OF_PROCESSORS)
    } else {
        $procWrap.CPUPercent = $delta * 100 /$env:NUMBER_OF_PROCESSORS
    }

    $procWrap.PrevCPU = $procWrap.CPU
    $procWrap.PrevTime = [DateTime]::UtcNow        
    return $procWrap
}

$wrapedProcess = Get-Process | % {& $wrapProcess $_}


<#
 The function
#>

function Top{

    [CmdletBinding()]
    param(
        [Parameter(Position=0)]
        [Switch]$Descending,
        [Parameter(Position=1)]
        [int]$Count
    )
    if($Count -eq $null -or $count -eq 0){
        Write-Verbose 'Output all processes'
        $Script:wrapedProcess | %{& $Script:getCpuUsage $_} |select -Property Name, id, CPUPercent | sort CPUPercent -Descending:$Descending | Format-Table -AutoSize
    } else {
        Write-Verbose "Output first $count processes"
        $Script:wrapedProcess | %{& $Script:getCpuUsage $_} |select -Property Name, id, CPUPercent | sort CPUPercent -Descending:$Descending | select -First $Count | Format-Table -AutoSize
    }
}

function Lock{
    
    [CmdletBinding()]
    param()

    rundll32.exe user32.dll, LockWorkStation
}

function logoff {
    [CmdletBinding()]
    param()

    shutdown /l /f
}

function reboot{
    [CmdletBinding()]
    param()

    shutdown /r /f /t 0
}

function off(){
    shutdown /p /f
}

<#
    Applications
#>
#$appConfPath = 'c:\Users\ext_logovskoy\Documents\WindowsPowerShell\Modules\ProcessCpuUsage\config\appsConfig.json'
$appConfPath = Join-Path $PSScriptRoot '\config\appsConfig.json'
$appsConfig = (Get-Content $appConfPath) -join "`n" | ConvertFrom-Json | Convert-ToPSObject

function Edit-AppsConfig(){
    npp -Path $appConfPath
}

function open{
    [cmdletbinding()]
    Param()
    DynamicParam{
        New-DynamicParam -Name Name -Mandatory -Position 0 -ValidateSet ($appsConfig.apps |%{$_.code}) -Type ([string[]])
    }
    begin{     
        Add-Parameter $PSBoundParameters
    }
    process{
        $Name |%{
            __openSingle $_
        }
    }
}

function __openSingle([string]$Name){
    $app = $appsConfig.apps |? {$_.code -eq $Name}
    if([string]::IsNullOrEmpty($app.params)){
        Start-Process $app.path 
    } else {
        Start-Process $app.path $app.params 
    }
}

function merge([string] $left, [string]$right){
    & ($appsConfig.apps |? {$_.code -eq 'merge'}).path $left $right
}

function npp{
    Param(
        [string]
        $Path,
        [switch]
        $SystemTray,
        [switch]
        $NoSession
    )

    $expr = "c:\Program Files\Notepad++\notepad++.exe"

    & $expr $(if($SystemTray.IsPresent) {'-systemtray'} else {''}) `
    $(if($NoSession.IsPresent) {'-nosession'} else {''}) `
    $Path
}

function iis(){
	& "$env:windir\system32\inetsrv\InetMgr.exe"
} 

function od{
    C:\Users\ext_logovskoy\AppData\Local\Microsoft\OneDrive\OneDrive.exe
}

function outlook{
    [CmdletBinding(DefaultParameterSetName="Restart")]
    Param(
        [Parameter(ParameterSetName="Restart")]
        [Switch]$Restart, 
        [Parameter(ParameterSetName="Kill")]
        [Switch]$Kill 
    )
 
    if($Restart -or $kill){
        Get-Process -Name OUTLOOK -ErrorAction SilentlyContinue | kill -Force | Out-Null
    }
    if(-not $Kill){
        & 'c:\Program Files\Microsoft Office\Office15\OUTLOOK.EXE'
    }    
}

function run(){
    $appsConfig.apps | % {
        if($_['start'] -ne $null -and $_.start -eq $true){
            open $_.code
        }
    }
}

function Add-Parameter {
    Param(
        [Parameter(Position=0, Mandatory=$true)]
        [validatescript({
            if($_ -eq $null -or $_.GetType().Name -ne 'PSBoundParametersDictionary'){
                Throw "DPDictionary must be a System.Management.Automation.RuntimeDefinedParameterDictionary object, or not exist"
            }
            $True
        })]
        $DPDictionary
    )

    foreach($param in $DPDictionary.Keys)
    {
        if (-not ( Get-Variable -name $param -Scope 1 -ErrorAction SilentlyContinue ) )
        {
            New-Variable -Name $param -Value $DPDictionary.$param -Scope 1 -Force
            Write-Verbose "Adding variable for dynamic parameter '$param' with value '$($DPDictionary.$param)'"
        }
    }
}

function gac{
    [cmdletbinding()]
    Param(
        [Parameter(Position=0, 
                   Mandatory=$True,
                   ValueFromPipeline=$true)]
        [string]$Path,
        [switch]$Install
    )
    begin{
        [System.Reflection.Assembly]::Load("System.EnterpriseServices, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b03f5f7f11d50a3a")
        $publish = New-Object System.EnterpriseServices.Internal.Publish
    }
    process{
        if(-not (Test-Path $Path)){
            Write-Error "File '$Path' Not found"
            return
        }
        if($Install){
            $publish.GacInstall($Path)
        } else {
            $publish.GacRemove($Path)
        }
    }
}

function edit{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true)]
        [ValidateSet("AppsConfig", "PublicationConf", "FrontendConfig", "BackendConfig")]
        [String]
        $Config
    )

    switch($Config){
        "AppsConfig" {
            Edit-AppsConfig | Out-Null
        }
        "PublicationConf"{
            Edit-PublicationConf | Out-Null
        }
        "FrontendConfig"{
            Edit-FrontendConfig | Out-Null
        }
        "BackendConfig"{
            Edit-BackendConfig | Out-Null
        }
    }
}

function beep{
    [Console]::Beep()
    [Console]::Beep()
    [Console]::Beep()
}

# Set proxy for Invoke-WebRequest command
$global:PSDefaultParameterValues = @{
        'Invoke-WebRequest:Proxy'='http://hqproxy.avp.ru:8080'
        '*:ProxyUseDefaultCredentials'=$true
}

<#
    Enable git powershell
#>
#(Resolve-Path "$env:LOCALAPPDATA\GitHub\shell.ps1")
