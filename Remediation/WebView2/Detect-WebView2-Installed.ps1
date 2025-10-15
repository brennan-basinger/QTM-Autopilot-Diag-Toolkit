$paths = @(
  "$Env:ProgramFiles\Microsoft\EdgeWebView\Application\msedgewebview2.exe",
  "$Env:ProgramFiles(x86)\Microsoft\EdgeWebView\Application\msedgewebview2.exe"
) | Get-ChildItem -ErrorAction SilentlyContinue
function HasMin([string]$v){ try{([version]$v -ge [version]'120.0.0.0')}catch{$false} }
if(-not $paths){
  foreach($k in @(
    'HKLM:\SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}')){
    try{ $pv=(gp $k -EA Stop).pv; if($pv -and (HasMin $pv)){ exit 0 } }catch{}
  } exit 1
}else{
  $ver=($paths|select -First 1).VersionInfo.FileVersion
  if(HasMin $ver){ exit 0 } else { exit 1 }
}