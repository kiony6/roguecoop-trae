$ErrorActionPreference = "Stop"

$godot = "D:\Godot\Godot_v4.7.2-stable_win64_console.exe"
$proj  = "D:\games\RogueCoop"
$out   = Join-Path $env:TEMP "roguecoop_nettest"

New-Item -ItemType Directory -Force -Path $out | Out-Null
Remove-Item (Join-Path $out "*") -Force -ErrorAction SilentlyContinue

$hostOut = Join-Path $out "host.log"
$hostErr = Join-Path $out "host.err"
$cliOut  = Join-Path $out "client.log"
$cliErr  = Join-Path $out "client.err"

$hostProc = Start-Process -FilePath $godot -PassThru -NoNewWindow `
    -ArgumentList @("--headless", "--path", $proj, "res://tools/net_test/net_test_host.tscn") `
    -RedirectStandardOutput $hostOut -RedirectStandardError $hostErr

Start-Sleep -Milliseconds 1500

$client = Start-Process -FilePath $godot -PassThru -NoNewWindow `
    -ArgumentList @("--headless", "--path", $proj, "res://tools/net_test/net_test_client.tscn") `
    -RedirectStandardOutput $cliOut -RedirectStandardError $cliErr

$client.WaitForExit(30000) | Out-Null
$hostProc.WaitForExit(30000) | Out-Null

if (Test-Path $hostOut) { Write-Host "--- host.log ---"; Get-Content $hostOut | ForEach-Object { Write-Host $_ } }
if (Test-Path $cliOut)  { Write-Host "--- client.log ---"; Get-Content $cliOut | ForEach-Object { Write-Host $_ } }

# 依据日志中的 PASS 断言判定（Start-Process -PassThru 在重定向场景下 ExitCode 可能为空）
$hostOk = (Test-Path $hostOut) -and (Select-String -Path $hostOut -Pattern "[NetTest-Host] PASS" -SimpleMatch -Quiet)
$cliOk  = (Test-Path $cliOut)  -and (Select-String -Path $cliOut  -Pattern "[NetTest-Client] PASS" -SimpleMatch -Quiet)

if ($hostOk -and $cliOk) {
    Write-Host "[NetTest] ALL PASS"
    exit 0
}

Write-Host "[NetTest] FAIL host_passed=$hostOk client_passed=$cliOk"
if (Test-Path $hostErr) { Write-Host "--- host.err ---"; Get-Content $hostErr }
if (Test-Path $cliErr)  { Write-Host "--- client.err ---"; Get-Content $cliErr }
exit 1
