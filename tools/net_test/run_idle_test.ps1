param([string]$Transport = "ws")
$ErrorActionPreference = "Stop"

$godot = "D:\Godot\Godot_v4.7.2-stable_win64_console.exe"
$proj  = "D:\games\RogueCoop"
$port  = 25602
$out   = Join-Path $env:TEMP "roguecoop_idle"

New-Item -ItemType Directory -Force -Path $out | Out-Null
Remove-Item (Join-Path $out "*") -Force -ErrorAction SilentlyContinue

$srvOut = Join-Path $out "server.log"
$srvErr = Join-Path $out "server.err"
$cliOut = Join-Path $out "client.log"
$cliErr = Join-Path $out "client.err"

$srvProc = Start-Process -FilePath $godot -PassThru -NoNewWindow `
    -ArgumentList @("--headless", "--path", $proj, "res://scenes/dedicated.tscn", "--", "--port=$port", "--transport=$Transport") `
    -RedirectStandardOutput $srvOut -RedirectStandardError $srvErr

Start-Sleep -Milliseconds 1500

$cli1 = Start-Process -FilePath $godot -PassThru -NoNewWindow `
    -ArgumentList @("--headless", "--path", $proj, "res://tools/net_test/net_test_client.tscn", "--", "--solo=1", "--port=$port", "--transport=$Transport") `
    -RedirectStandardOutput $cliOut -RedirectStandardError $cliErr
$cli1.WaitForExit(40000) | Out-Null

Start-Sleep -Seconds 15

$cli2Out = Join-Path $out "client2.log"
$cli2Err = Join-Path $out "client2.err"
$cli2 = Start-Process -FilePath $godot -PassThru -NoNewWindow `
    -ArgumentList @("--headless", "--path", $proj, "res://tools/net_test/net_test_client.tscn", "--", "--solo=1", "--port=$port", "--transport=$Transport") `
    -RedirectStandardOutput $cli2Out -RedirectStandardError $cli2Err
$cli2.WaitForExit(40000) | Out-Null

if (Test-Path $srvOut) { Write-Host "--- server.log ---"; Get-Content $srvOut | ForEach-Object { Write-Host $_ } }
if (Test-Path $cliOut) { Write-Host "--- client.log ---"; Get-Content $cliOut | ForEach-Object { Write-Host $_ } }
if (Test-Path $cli2Out) { Write-Host "--- client2.log ---"; Get-Content $cli2Out | ForEach-Object { Write-Host $_ } }

Stop-Process -Id $srvProc.Id -Force -ErrorAction SilentlyContinue

$srvOk   = (Test-Path $srvOut) -and (Select-String -Path $srvOut -Pattern "[Dedicated] listening" -SimpleMatch -Quiet)
$resetOk = (Test-Path $srvOut) -and (Select-String -Path $srvOut -Pattern "[Dedicated] idle reset after" -SimpleMatch -Quiet)
$cli1Ok  = (Test-Path $cliOut) -and (Select-String -Path $cliOut -Pattern "[NetTest-Client] PASS" -SimpleMatch -Quiet)
$cli2Ok  = (Test-Path $cli2Out) -and (Select-String -Path $cli2Out -Pattern "[NetTest-Client] PASS" -SimpleMatch -Quiet)

if ($srvOk -and $resetOk -and $cli1Ok -and $cli2Ok) {
    Write-Host "[IdleTest] ALL PASS"
    exit 0
}

Write-Host "[IdleTest] FAIL server_ok=$srvOk idle_reset_ok=$resetOk client1_ok=$cli1Ok client2_ok=$cli2Ok"
if (Test-Path $srvErr)  { Write-Host "--- server.err ---"; Get-Content $srvErr }
if (Test-Path $cliErr)  { Write-Host "--- client.err ---"; Get-Content $cliErr }
if (Test-Path $cli2Err) { Write-Host "--- client2.err ---"; Get-Content $cli2Err }
exit 1
