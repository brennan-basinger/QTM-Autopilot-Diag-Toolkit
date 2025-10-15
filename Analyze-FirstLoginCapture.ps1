param([Parameter(Mandatory=$true)][string]$Path)
function ReadText($p){ if(Test-Path $p){ Get-Content -Raw -EA SilentlyContinue } }
function ReadZip($z,$e){
  Add-Type -AssemblyName System.IO.Compression.FileSystem -EA SilentlyContinue
  if(-not (Test-Path $z)){ return $null }
  try{ $za=[IO.Compression.ZipFile]::OpenRead($z); $en=$za.Entries|?{ $_.FullName -ieq $e }
       if($en){ $r=(New-Object IO.StreamReader($en.Open())).ReadToEnd(); $za.Dispose(); return $r }
       $za.Dispose() }catch{}
  return $null
}
$inZip = (Test-Path $Path -PathType Leaf) -and ($Path.EndsWith('.zip'))
function read($rel){
  if($inZip){ return ReadZip $Path $rel } else { return ReadText (Join-Path $Path $rel) }
}
$report=[ordered]@{}
$wv=read "Edge\WebView2_Info.txt"; if(-not $wv){$wv=read "10_webview2_registry.txt"}
if($wv -match '\d+\.\d+\.\d+\.\d+'){ $report.WebView2Version=$Matches[0] }
$eup=read "Edge\EdgeUpdate_Policies.txt"; if(-not $eup){$eup=read "17_edgeupdate_policies.txt"}
$report.EdgeUpdatePolicyLines=($eup -split "`n"|?{$_ -match 'EdgeUpdate|UpdateDefault|TargetChannel'})[0..5] -join "`n"
$ds=read "dsregcmd_status.txt"
$report.JoinType = if($ds -match 'AzureAdJoined\s*:\s*YES'){'AADJoined=YES'}else{'AADJoined=NO/Unknown'}
$dm=read "DO\DO_DownloadMode.txt"; $st=read "DO\DO_Status.txt"
$report.DeliveryOptimization=@{ DownloadMode=$dm; StatusExcerpt=($st -split "`n")[0..10] -join "`n" }
$csv=read "Network\Connectivity_443.csv"; if($csv){ $fails=($csv | ConvertFrom-Csv)|?{ $_.TcpTestSucceeded -eq 'False' }|% Target; $report.Connectivity443Failures = ($fails -join ', ') }
$ime=read "IME\IntuneManagementExtension.log"; if($ime){ $report.IMEFlags = @('ESP'[$ime -match 'ESP'], 'Win32'[$ime -match 'Win32App']) -join ',' }
$report | ConvertTo-Json -Depth 4
