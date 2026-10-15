param([string]$Transport = "ws")
$ErrorActionPreference = "Stop"

$godot = "D:\Godot\Godot_v4.7.2-stable_win64_console.exe"
$proj  = "D:\games\RogueCoop"
$port  = 25604
$out   = Join-Path $env:TEMP "roguecoop_lobby"
$data  = Join-Path $out "accounts.json"
$codeFile = Join-Path $out "code.txt"

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

# 大厅专服（常驻进程，收尾必须显式杀掉）——客户端固定 ws，故必须 --transport=ws
$srvProc = Start-Process -FilePath $godot -PassThru -NoNewWindow `
    -ArgumentList @("--headless", "--path", $proj, "res://scenes/dedicated.tscn",
                    "--", "--mode=lobby", "--port=$port", "--transport=$Transport", "--data=$data") `
    -RedirectStandardOutput $srvOut -RedirectStandardError $srvErr

Start-Sleep -Milliseconds 1500

$pass = "pw123456"

# ---- 独立负例：notlogged / badcode ----
$uN = "n" + (Get-Random -Minimum 100000 -Maximum 999999)
$nProc = New-LobbyClient "notlogged" @("--stage=notlogged", "--user=$uN", "--pass=$pass")
$nProc.WaitForExit(60000) | Out-Null
$nOk = Test-LogHas (Join-Path $out "notlogged.log") "[LobbyTest] PASS"

$uB = "b" + (Get-Random -Minimum 100000 -Maximum 999999)
$bProc = New-LobbyClient "badcode" @("--stage=badcode", "--user=$uB", "--pass=$pass")
$bProc.WaitForExit(60000) | Out-Null
$bOk = Test-LogHas (Join-Path $out "badcode.log") "[LobbyTest] PASS"

# ---- 房间主流程：host 先建房并写出组队码，再并发 3 seat + 1 full ----
$uH = "h" + (Get-Random -Minimum 100000 -Maximum 999999)
$hostProc = New-LobbyClient "host" @("--stage=host", "--user=$uH", "--pass=$pass", "--codefile=$codeFile")

$code = ""
$deadline = (Get-Date).AddSeconds(20)
while ((Get-Date) -lt $deadline) {
    if (Test-Path $codeFile) {
        $raw = (Get-Content $codeFile -Raw -ErrorAction SilentlyContinue)
        if ($raw) { $raw = $raw.Trim() }
        if ($raw -match '^[1-9][0-9]{5}$') { $code = $raw; break }
    }
    Start-Sleep -Milliseconds 250
}

$seatProcs = @()
$uS1 = "s" + (Get-Random -Minimum 100000 -Maximum 999999)
$uS2 = "t" + (Get-Random -Minimum 100000 -Maximum 999999)
$uS3 = "w" + (Get-Random -Minimum 100000 -Maximum 999999)
$seatProcs += New-LobbyClient "seat1" @("--stage=seat", "--user=$uS1", "--pass=$pass", "--code=$code", "--expect=not_host", "--linger=30")
$seatProcs += New-LobbyClient "seat2" @("--stage=seat", "--user=$uS2", "--pass=$pass", "--code=$code", "--linger=30")
$seatProcs += New-LobbyClient "seat3" @("--stage=seat", "--user=$uS3", "--pass=$pass", "--code=$code", "--linger=30")

# 等 3 个 seat 都入房（服务端打印 3 条 room joined）后再启动 full，确保它面对满房拿 ROOM_FULL
$deadline = (Get-Date).AddSeconds(20)
while ((Get-Date) -lt $deadline) {
    if (Test-Path $srvOut) {
        $joined = (Select-String -Path $srvOut -Pattern "room joined" -SimpleMatch).Count
        if ($joined -ge 3) { break }
    }
    Start-Sleep -Milliseconds 250
}

$uF = "f" + (Get-Random -Minimum 100000 -Maximum 999999)
$fullProc = New-LobbyClient "full" @("--stage=full", "--user=$uF", "--pass=$pass", "--code=$code", "--delay=1")

$hostProc.WaitForExit(150000) | Out-Null
foreach ($p in $seatProcs) { $p.WaitForExit(60000) | Out-Null }
$fullProc.WaitForExit(60000) | Out-Null

# 服务端是常驻进程：判定后必须显式杀掉
Stop-Process -Id $srvProc.Id -Force -ErrorAction SilentlyContinue

Show-Log "notlogged"; Show-Log "badcode"; Show-Log "host"
Show-Log "seat1"; Show-Log "seat2"; Show-Log "seat3"; Show-Log "full"
if (Test-Path $srvOut) { Write-Host "--- server.log ---"; Get-Content $srvOut | ForEach-Object { Write-Host $_ } }

$srvOk      = Test-LogHas $srvOut "[Dedicated] mode=lobby"
$createdOk  = Test-LogHas $srvOut "room created"
$startedOk  = Test-LogHas $srvOut "room started"
$finishedOk = Test-LogHas $srvOut "room finished"
$hostOk = Test-LogHas (Join-Path $out "host.log") "[LobbyTest] PASS"
$s1Ok   = Test-LogHas (Join-Path $out "seat1.log") "[LobbyTest] PASS"
$s2Ok   = Test-LogHas (Join-Path $out "seat2.log") "[LobbyTest] PASS"
$s3Ok   = Test-LogHas (Join-Path $out "seat3.log") "[LobbyTest] PASS"
$fOk    = Test-LogHas (Join-Path $out "full.log") "[LobbyTest] PASS"

if ($nOk -and $bOk -and $hostOk -and $s1Ok -and $s2Ok -and $s3Ok -and $fOk `
        -and $srvOk -and $createdOk -and $startedOk -and $finishedOk) {
    Write-Host "[LobbyTest] ALL PASS code=$code"
    exit 0
}

Write-Host "[LobbyTest] FAIL notlogged=$nOk badcode=$bOk host=$hostOk seat1=$s1Ok seat2=$s2Ok seat3=$s3Ok full=$fOk server=$srvOk created=$createdOk started=$startedOk finished=$finishedOk"
if (Test-Path $srvErr) { Write-Host "--- server.err ---"; Get-Content $srvErr }
exit 1
