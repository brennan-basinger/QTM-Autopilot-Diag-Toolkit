<#
.SYNOPSIS
  Autopilot + First Login Diagnostic Collector (v3)
.DESCRIPTION
  Collects Autopilot/ESP/IME/Edge WebView2, WU, Delivery Optimization,
  network reachability, and AAD join data. Intended to run during ESP
  (Shift+F10) and again after first login.
.PARAMETER Phase
  Baseline | DuringESP | AfterLogin | PostFix
#>
param(
  [ValidateSet("Baseline","DuringESP","AfterLogin","PostFix")]
  [string]$Phase = "Baseline"
)

$ErrorActionPreference = 'SilentlyContinue'

function New-OutputFolders {
  $root  = 'C:\QTM-FirstLoginCapture'
  $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
  $out   = Join-Path $root "$stamp-$Phase"
  New-Item -ItemType Directory -Force -Path $out,$out\Logs,$out\Events,$out\Autopilot,$out\Network,$out\WU,$out\DO,$out\Edge,$out\IME,$out\EdgeUpdate | Out-Null
  return @{Root=$root;Stamp=$stamp;Out=$out}
}

function Write-Section($msg) {
  $line = ('='*8)
  "$line $msg $line"
}

function Save-Text($path, [string]$content){
  $dir = Split-Path -Path $path -Parent
  if(!(Test-Path $dir)){ New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $content | Out-File -FilePath $path -Encoding UTF8 -Force
}

function Export-EventLogChannel([string]$channel, [string]$destFolder){
  try{
    $san = $channel -replace '[^a-zA-Z0-9\-]','_'
    $evtx = Join-Path $destFolder "$san.evtx"
    wevtutil epl $channel $evtx
    return $evtx
  } catch {
    return $null
  }
}

function Get-WebView2Info {
  $result = [ordered]@{}
  $guids = @(
    'HKLM:\SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}',
    'HKCU:\SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}'
  )
  foreach($g in $guids){
    try{
      $pv = (Get-ItemProperty -Path $g -ErrorAction Stop).pv
      if($pv){ $result["$g"] = $pv }
    } catch {}
  }
  $paths = @(
    "$Env:ProgramFiles\Microsoft\EdgeWebView\Application\*\msedgewebview2.exe",
    "$Env:ProgramFiles(x86)\Microsoft\EdgeWebView\Application\*\msedgewebview2.exe"
  ) | Get-ChildItem -ErrorAction SilentlyContinue
  if($paths){
    $fv = ($paths | Sort-Object FullName -Descending | Select-Object -First 1).VersionInfo.FileVersion
    $result['FileVersion'] = $fv
    $result['FilePath']    = ($paths | Sort-Object FullName -Descending | Select-Object -First 1).FullName
  }
  $edgeUpdatePol = 'HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate'
  $pol = @()
  try{
    if(Test-Path $edgeUpdatePol){ $pol = Get-ItemProperty -Path $edgeUpdatePol | Select-Object * }
  } catch {}
  $svc = Get-Service -Name 'edgeupdate','edgeupdatem' -ErrorAction SilentlyContinue
  return [pscustomobject]@{
    Keys        = $result
    EdgeUpdatePolicies = $pol
    EdgeUpdateServices = $svc | Select-Object Name,Status,StartType
  }
}

function Capture-DO {
  param([string]$dest)
  try{ Get-DODownloadMode | Out-File "$dest\DO_DownloadMode.txt" } catch {}
  try{ Get-DOConfig | Out-File "$dest\DO_Config.txt" } catch {}
  try{ Get-DeliveryOptimizationStatus | Format-List * | Out-File "$dest\DO_Status.txt" } catch {}
  try{ Get-DeliveryOptimizationPerfSnap | Format-List * | Out-File "$dest\DO_PerfSnap.txt" } catch {}
}

function Capture-Network {
  param([string]$dest)
  $targets = @(
    'login.microsoftonline.com','device.login.microsoftonline.com','enterpriseregistration.windows.net',
    'client.wns.windows.com','wns.windows.com',
    'dl.delivery.mp.microsoft.com','emdl.ws.microsoft.com',
    'windowsupdate.microsoft.com','download.windowsupdate.com','ctldl.windowsupdate.com'
  )
  $results = foreach($t in $targets){
    try{
      $r = Test-NetConnection -ComputerName $t -Port 443 -InformationLevel Detailed
      [pscustomobject]@{
        Target=$t; TcpTestSucceeded=$r.TcpTestSucceeded; RemotePort=$r.RemotePort; RemoteAddress=$r.RemoteAddress; PingSucceeded=$r.PingSucceeded
      }
    } catch {
      [pscustomobject]@{Target=$t; TcpTestSucceeded=$false; RemotePort=443; RemoteAddress=$null; PingSucceeded=$false}
    }
  }
  $results | Export-Csv -NoTypeInformation -Path "$dest\Connectivity_443.csv"
  & ipconfig /all > "$dest\ipconfig_all.txt" 2>&1
  & netsh winhttp show proxy > "$dest\winhttp_proxy.txt" 2>&1
  & netsh interface ip show dnsservers > "$dest\dnsservers.txt" 2>&1
  & nslookup login.microsoftonline.com > "$dest\nslookup_login_msol.txt" 2>&1
  & w32tm /query /status > "$dest\time_status.txt" 2>&1
  & tzutil /g > "$dest\timezone.txt" 2>&1
}

function Capture-IME {
  param([string]$dest)
  $ime = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs"
  if(Test-Path $ime){
    Copy-Item "$ime\*" "$dest" -Recurse -Force -ErrorAction SilentlyContinue
  }
}

function Capture-EdgeUpdateLogs {
  param([string]$dest)
  $elog = "C:\Program Files (x86)\Microsoft\EdgeUpdate\Log"
  if(Test-Path $elog){
    Copy-Item "$elog\*.log" "$dest" -Force -ErrorAction SilentlyContinue
  }
}

function Capture-AutopilotAndMDM {
  param([string]$dest)
  $ap = "C:\Windows\Provisioning\Autopilot"
  if(Test-Path $ap){ Copy-Item "$ap\*" "$dest\Autopilot" -Recurse -Force -ErrorAction SilentlyContinue }
  try{ mdmdiagnosticstool.exe -area Autopilot;DeviceEnrollment;DeviceProvisioning -cab "$dest\MDMDiag-$env:COMPUTERNAME-$Phase.cab" } catch {}
}

function Capture-EventLogs {
  param([string]$dest)
  $channels = @(
    'Microsoft-Windows-DeviceManagement-Enterprise-Diagnostics-Provider/Admin',
    'Microsoft-Windows-DeviceManagement-Enterprise-Diagnostics-Provider/Operational',
    'Microsoft-Windows-ModernDeployment-Diagnostics-Provider/Autopilot',
    'Microsoft-Windows-Provisioning-Diagnostics-Provider/Admin',
    'Microsoft-Windows-User Device Registration/Admin',
    'Microsoft-Windows-AAD/Operational',
    'Microsoft-Windows-Shell-Core/Operational'
  )
  foreach($c in $channels){ Export-EventLogChannel -channel $c -destFolder $dest | Out-Null }
}

function Capture-WindowsUpdate {
  param([string]$dest)
  try{
    Get-WindowsUpdateLog -LogPath "$dest\WindowsUpdate.log" -ErrorAction Stop | Out-Null
  } catch {
    'Get-WindowsUpdateLog failed. Consider running as 64-bit PowerShell with admin rights.' | Out-File "$dest\WindowsUpdate_log_note.txt"
  }
}

function Capture-OSAndApps {
  param([string]$dest)
  try{ Get-ComputerInfo | Out-File "$dest\ComputerInfo.txt" } catch {}
  try{ dsregcmd /status > "$dest\dsregcmd_status.txt" 2>&1 } catch {}
  try{ dsregcmd /debug > "$dest\dsregcmd_debug.txt" 2>&1 } catch {}
  try{ Get-AppxPackage MSTeams* , *Outlook* | Select-Object Name, Version, PackageFamilyName | Format-Table -Auto | Out-String | Out-File "$dest\Appx_Teams_Outlook.txt" } catch {}
  try{ winget --info > "$dest\winget_info.txt" 2>&1 } catch {}
}

function Capture-EdgeWebView2 {
  param([string]$dest)
  $info = Get-WebView2Info
  $info | Format-List * | Out-File "$dest\Edge\WebView2_Info.txt"
  try{
    reg query "HKLM\SOFTWARE\Policies\Microsoft\EdgeUpdate" /s > "$dest\Edge\EdgeUpdate_Policies.txt" 2>&1
    schtasks /query /tn "\Microsoft\EdgeUpdate\*" /fo LIST /v > "$dest\Edge\EdgeUpdate_Tasks.txt" 2>&1
    Get-Service edgeupdate,edgeupdatem | Format-Table -Auto | Out-File "$dest\Edge\EdgeUpdate_Services.txt"
  } catch {}
}

# Main
$ctx = New-OutputFolders
$Out = $ctx.Out

Write-Section "Starting capture: $Phase" | Out-File "$Out\Summary.txt" -Append
Capture-OSAndApps -dest $Out
Capture-Network  -dest "$Out\Network"
Capture-IME      -dest "$Out\IME"
Capture-AutopilotAndMDM -dest $Out
Capture-EventLogs -dest "$Out\Events"
Capture-WindowsUpdate -dest "$Out\WU"
Capture-DO -dest "$Out\DO"
Capture-EdgeWebView2 -dest $Out
Capture-EdgeUpdateLogs -dest "$Out\EdgeUpdate"

# Zip
$zip = Join-Path $ctx.Root ("QTM_FirstLogin_"+$ctx.Stamp+"_"+$Phase+".zip")
Compress-Archive -Path $Out\* -DestinationPath $zip -Force
Write-Section "Capture complete: $zip" | Out-File "$Out\Summary.txt" -Append
Write-Output "Capture complete: $zip"
