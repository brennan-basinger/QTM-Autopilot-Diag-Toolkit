param([string]$OfflineInstallerPath = ".\MicrosoftEdgeWebView2RuntimeInstallerX64.exe",[switch]$Force)
$ErrorActionPreference='SilentlyContinue'
function IsInstalled{ (gci "$Env:ProgramFiles\Microsoft\EdgeWebView\Application\msedgewebview2.exe" -EA SilentlyContinue) -or (gci "$Env:ProgramFiles(x86)\Microsoft\EdgeWebView\Application\msedgewebview2.exe" -EA SilentlyContinue) }
if((IsInstalled) -and -not $Force){ exit 0 }
if(Test-Path $OfflineInstallerPath){
  & $OfflineInstallerPath /silent /install
  $exit=$LASTEXITCODE
}else{
  $temp=Join-Path $env:TEMP "WebView2_Bootstrapper.exe"
  $url="https://go.microsoft.com/fwlink/p/?LinkId=2124703"
  (New-Object Net.WebClient).DownloadFile($url,$temp)
  & $temp /silent /install
  $exit=$LASTEXITCODE
}
Start-Sleep 5
if(IsInstalled){ exit 0 } else { exit 1 }