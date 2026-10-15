param([string]$Transport = "ws")
$ErrorActionPreference = "Stop"

$godot = "D:\Godot\Godot_v4.7.2-stable_win64_console.exe"
$proj  = "D:\games\RogueCoop"
$port  = 25605
$out   = Join-Path $env:TEMP "roguecoop_lobby_cc"
$data  = Join-Path $out "accounts.json"

New-Item -ItemType Directory -Force -Path $out | Out-Null
Remove-Item (Join-Path $out "*") -Force -ErrorAction SilentlyContinue

$srvOut = Join-Path $out "server.log"
$srvErr = Join-Path $out "server.err"

function Test-LogHas([string]$path, [string]$pattern) {
    return (Test-Path $path) -and (Select-String -Path $path -Pattern $pattern -SimpleMatch -Quiet)
}

function Show-Log([string]$tag) {
    $o = Join-Path $out "$tag.log"
    if (Test-Path $o) { Write-Host "--- $tag.log ---"; Get-Content $o | ForEach-Object { Write-Host $_ } }
    $e = Join-Path $out "$tag.err"
    if ((Test-Path $e) -and ((Get-Item $e).Length -gt 0)) {
        Write-Host "--- $tag.err ---"; Get-Content $e | ForEach-Object { Write-Host $_ }
    }
}

function New-LobbyClient([string]$tag, [string[]]$extra) {
    $o = Join-Path $out "$tag.log"
    $e = Join-Path $out "$tag.err"
    $argList = @("--headless", "--path", $proj, "res://tools/net_test/net_test_lobby_client.tscn",
                 "--", "--ip=127.0.0.1", "--port=$port") + $extra
    return (Start-Process -FilePath $godot -PassThru -NoNewWindow -ArgumentList $argList `
        -RedirectStandardOutput $o -RedirectStandardError $e)
}

$srvProc = Start-Process -FilePath $godot -PassThru -NoNewWindow `
    -ArgumentList @("--headless", "--path", $proj, "res://scenes/dedicated.tscn",
                    "--", "--mode=lobby", "--port=$port", "--transport=$Transport", "--data=$data") `
    -RedirectStandardOutput $srvOut -RedirectStandardError $srvErr

Start-Sleep -Milliseconds 1500

$pass = "pw123456"
$procs = @()
$tags = @("cc1", "cc2", "cc3", "cc4")
for ($i = 0; $i -lt 4; $i++) {
    $u = "c$i" + (Get-Random -Minimum 100000 -Maximum 999999)
    # 4 个客户端各自建房并开局；--linger 让 4 个房间同时存活，以复现 rooms=4
    $procs += New-LobbyClient $tags[$i] @("--stage=concurrent", "--user=$u", "--pass=$pass", "--linger=6")
}

foreach ($p in $procs) { $p.WaitForExit(90000) | Out-Null }

Stop-Process -Id $srvProc.Id -Force -ErrorAction SilentlyContinue

foreach ($t in $tags) { Show-Log $t }
if (Test-Path $srvOut) { Write-Host "--- server.log ---"; Get-Content $srvOut | ForEach-Object { Write-Host $_ } }

$ok = $true
foreach ($t in $tags) {
    if (-not (Test-LogHas (Join-Path $out "$t.log") "[LobbyTest] PASS")) { $ok = $false }
}
$roomsOk = Test-LogHas $srvOut "rooms=4"
$srvOk   = Test-LogHas $srvOut "[Dedicated] mode=lobby"

if ($ok -and $roomsOk -and $srvOk) {
    Write-Host "[LobbyConcurrentTest] ALL PASS"
    exit 0
}

Write-Host "[LobbyConcurrentTest] FAIL clients=$ok rooms4=$roomsOk server=$srvOk"
if (Test-Path $srvErr) { Write-Host "--- server.err ---"; Get-Content $srvErr }
exit 1
