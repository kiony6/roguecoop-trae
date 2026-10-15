param([string]$Transport = "ws")
$ErrorActionPreference = "Stop"

$godot = "D:\Godot\Godot_v4.7.2-stable_win64_console.exe"
$proj  = "D:\games\RogueCoop"
$port  = 25603
$out   = Join-Path $env:TEMP "roguecoop_acct"
$data  = Join-Path $out "accounts.json"

New-Item -ItemType Directory -Force -Path $out | Out-Null
Remove-Item (Join-Path $out "*") -Force -ErrorAction SilentlyContinue

$srvOut = Join-Path $out "server.log"
$srvErr = Join-Path $out "server.err"

$srvProc = Start-Process -FilePath $godot -PassThru -NoNewWindow `
    -ArgumentList @("--headless", "--path", $proj, "res://scenes/dedicated.tscn", "--", "--port=$port", "--transport=$Transport", "--data=$data") `
    -RedirectStandardOutput $srvOut -RedirectStandardError $srvErr

Start-Sleep -Milliseconds 1500

$user = "u" + (Get-Random -Minimum 100000 -Maximum 999999)
$pass = "pw123456"

function Invoke-Stage([string]$stage, [string]$file) {
    $o = Join-Path $out "$file.log"
    $e = Join-Path $out "$file.err"
    $proc = Start-Process -FilePath $godot -PassThru -NoNewWindow `
        -ArgumentList @("--headless", "--path", $proj, "res://tools/net_test/net_test_account_client.tscn", "--", "--stage=$stage", "--ip=127.0.0.1", "--port=$port", "--transport=$Transport", "--user=$user", "--pass=$pass") `
        -RedirectStandardOutput $o -RedirectStandardError $e
    $proc.WaitForExit(30000) | Out-Null
    if (Test-Path $o) { Write-Host "--- $file.log ---"; Get-Content $o | ForEach-Object { Write-Host $_ } }
    return (Test-Path $o) -and (Select-String -Path $o -Pattern "[AcctTest] PASS" -SimpleMatch -Quiet)
}

$s1 = Invoke-Stage "register" "s1"
$s2 = Invoke-Stage "badpass"  "s2"
$s3 = Invoke-Stage "mismatch" "s3"

Stop-Process -Id $srvProc.Id -Force -ErrorAction SilentlyContinue

if (Test-Path $srvOut) { Write-Host "--- server.log ---"; Get-Content $srvOut | ForEach-Object { Write-Host $_ } }

# 服务端取证：必须看到监听日志（含 accounts= 计数）与账号日志
$srvOk = (Test-Path $srvOut) -and (Select-String -Path $srvOut -Pattern "[Dedicated] listening" -SimpleMatch -Quiet)
$logOk = (Test-Path $srvOut) -and (Select-String -Path $srvOut -Pattern "[Dedicated] account" -SimpleMatch -Quiet)

if ($s1 -and $s2 -and $s3 -and $srvOk -and $logOk) {
    Write-Host "[AcctTest] ALL PASS user=$user"
    exit 0
}

Write-Host "[AcctTest] FAIL s1=$s1 s2=$s2 s3=$s3 srv=$srvOk log=$logOk"
if (Test-Path $srvErr) { Write-Host "--- server.err ---"; Get-Content $srvErr }
exit 1
