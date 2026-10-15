$ErrorActionPreference = "Stop"

$godot = "D:\Godot\Godot_v4.7.2-stable_win64_console.exe"
$proj  = "D:\games\RogueCoop"
$port  = 25601
$out   = Join-Path $env:TEMP "roguecoop_dedicated"

New-Item -ItemType Directory -Force -Path $out | Out-Null
Remove-Item (Join-Path $out "*") -Force -ErrorAction SilentlyContinue

$srvOut = Join-Path $out "server.log"
$srvErr = Join-Path $out "server.err"
$cliOut = Join-Path $out "client.log"
$cliErr = Join-Path $out "client.err"

$srvProc = Start-Process -FilePath $godot -PassThru -NoNewWindow `
    -ArgumentList @("--headless", "--path", $proj, "res://scenes/dedicated.tscn", "--", "--port=$port") `
    -RedirectStandardOutput $srvOut -RedirectStandardError $srvErr

Start-Sleep -Milliseconds 1500

$cliProc = Start-Process -FilePath $godot -PassThru -NoNewWindow `
    -ArgumentList @("--headless", "--path", $proj, "res://tools/net_test/net_test_client.tscn", "--", "--solo=1", "--port=$port") `
    -RedirectStandardOutput $cliOut -RedirectStandardError $cliErr

$cliProc.WaitForExit(40000) | Out-Null

if (Test-Path $srvOut) { Write-Host "--- server.log ---"; Get-Content $srvOut | ForEach-Object { Write-Host $_ } }
if (Test-Path $cliOut) { Write-Host "--- client.log ---"; Get-Content $cliOut | ForEach-Object { Write-Host $_ } }

# 服务器是常驻进程：判定后必须显式杀掉，避免残留
Stop-Process -Id $srvProc.Id -Force -ErrorAction SilentlyContinue

$srvOk = (Test-Path $srvOut) -and (Select-String -Path $srvOut -Pattern "[Dedicated] listening" -SimpleMatch -Quiet)
$cliOk = (Test-Path $cliOut) -and (Select-String -Path $cliOut -Pattern "[NetTest-Client] PASS" -SimpleMatch -Quiet)

if ($srvOk -and $cliOk) {
    Write-Host "[DedicatedTest] ALL PASS"
    exit 0
}

Write-Host "[DedicatedTest] FAIL server_ok=$srvOk client_ok=$cliOk"
if (Test-Path $srvErr) { Write-Host "--- server.err ---"; Get-Content $srvErr }
if (Test-Path $cliErr)  { Write-Host "--- client.err ---"; Get-Content $cliErr }
exit 1
