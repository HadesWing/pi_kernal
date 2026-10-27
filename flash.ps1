#Requires -RunAsAdministrator
# Raspberry Pi SD card flashing script - MUST run as Administrator
# Writes D:\rpi\os.img to the target SD card (raw disk image, not file copy)
# NOTE: keep this file pure ASCII - PowerShell 5.1 reads ANSI and garbles UTF-8 non-ASCII text.

$ErrorActionPreference = 'Stop'
$img        = 'D:\rpi\os.img'
$imgLen     = 0
$MB         = 1024 * 1024

Write-Host ""
Write-Host "=================== Raspberry Pi SD Flasher ===================" -ForegroundColor Cyan

# --- 1. Pre-checks ---
if (-not (Test-Path $img)) {
    Write-Host "[ABORT] Image file not found: $img" -ForegroundColor Red
    exit 1
}
$imgLen = (Get-Item $img).Length
Write-Host ("Image file : {0}" -f $img)
Write-Host ("Image size : {0:N2} GB ({1:N0} bytes)" -f ($imgLen / 1GB), $imgLen)

$cands = Get-Disk | Where-Object {
    $_.BusType -in @('USB', 'SD', 'MMC') -and (-not $_.IsBoot) -and (-not $_.IsSystem)
}
if (-not $cands) {
    Write-Host "[ABORT] No USB/SD disk found. Check the card reader connection." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Candidate removable disks:" -ForegroundColor Yellow
$cands | Select-Object Number, FriendlyName, @{n = 'SizeGB'; e = { [math]::Round($_.Size / 1GB, 2) } }, SerialNumber, PartitionStyle | Format-Table -AutoSize

if (@($cands).Count -gt 1) {
    Write-Host "[ABORT] More than one candidate disk. Unplug other USB storage devices and rerun." -ForegroundColor Red
    exit 1
}
$d = $cands[0]

if ($d.Size -lt $imgLen) {
    Write-Host ("[ABORT] Card size {0:N2} GB is smaller than image {1:N2} GB" -f ($d.Size / 1GB), ($imgLen / 1GB)) -ForegroundColor Red
    exit 1
}
if ($d.Number -le 1) {
    Write-Host "[ABORT] Target disk number is abnormal (possibly a system disk). Refusing to run." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Red
Write-Host "  WARNING: the WHOLE disk below will be ERASED, irrecoverable:" -ForegroundColor Red
Write-Host ("      Disk {0}  {1}  {2:N2} GB" -f $d.Number, $d.FriendlyName, ($d.Size / 1GB)) -ForegroundColor Red
Write-Host "      It will be overwritten with the Raspberry Pi OS image." -ForegroundColor Red
Write-Host "================================================================" -ForegroundColor Red
Write-Host ""
$ans = Read-Host ("Type the disk number [{0}] to confirm, or anything else to cancel" -f $d.Number)
if ($ans.Trim() -ne [string]$d.Number) {
    Write-Host "Cancelled. Nothing was done." -ForegroundColor Yellow
    exit 0
}

# --- 2. Wipe partition table ---
Write-Host ""
Write-Host "[1/4] Wiping partition table..." -ForegroundColor Cyan
$dp = 'D:\rpi\dp.txt'
$lines = @("select disk $($d.Number)", "clean")
Set-Content -Path $dp -Value $lines -Encoding ASCII
$out = & diskpart /s $dp 2>&1
$out | ForEach-Object { Write-Host ("      " + $_) -ForegroundColor DarkGray }
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ABORT] diskpart failed" -ForegroundColor Red
    exit 1
}

# --- 3. Raw write image ---
Write-Host "[2/4] Writing image (several minutes, DO NOT unplug the card)..." -ForegroundColor Cyan
$devPath = "\\.\PhysicalDrive" + $d.Number
$fs = $null
$src = $null
try {
    $fs = New-Object System.IO.FileStream($devPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::ReadWrite, 4096, $false)
    $src = [System.IO.File]::OpenRead($img)
    $buf = New-Object byte[] (4 * $MB)
    $total = 0
    $lastPct = -1
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($true) {
        $n = $src.Read($buf, 0, $buf.Length)
        if ($n -le 0) { break }
        $fs.Write($buf, 0, $n)
        $total += $n
        $pct = [int](100 * $total / $imgLen)
        if ($pct -ne $lastPct -and ($pct % 5 -eq 0)) {
            $speed = $total / $MB / $sw.Elapsed.TotalSeconds
            Write-Host ("      {0,3}%  {1:N0}/{2:N0} MB  {3:N1} MB/s" -f $pct, ($total / $MB), ($imgLen / $MB), $speed)
            $lastPct = $pct
        }
    }
    $fs.Flush($true)
    Write-Host ("      Done. Wrote {0:N0} MB in {1:N0} seconds" -f ($total / $MB), $sw.Elapsed.TotalSeconds) -ForegroundColor Green
}
finally {
    if ($src) { $src.Close() }
    if ($fs) { $fs.Close() }
}

# --- 4. Rescan partitions and assign drive letter ---
Write-Host "[3/4] Rescanning partitions..." -ForegroundColor Cyan
Update-HostStorageCache
Start-Sleep -Seconds 3
$parts = Get-Partition -DiskNumber $d.Number -ErrorAction SilentlyContinue
if (-not $parts) {
    Update-HostStorageCache
    Start-Sleep -Seconds 3
    $parts = Get-Partition -DiskNumber $d.Number -ErrorAction SilentlyContinue
}
$parts | Select-Object PartitionNumber, DriveLetter, @{n = 'SizeMB'; e = { [math]::Round($_.Size / 1MB, 0) } }, Type | Format-Table -AutoSize
$p1 = $parts | Where-Object { $_.PartitionNumber -eq 1 }
if ($p1 -and (-not $p1.DriveLetter)) {
    Add-PartitionAccessPath -DiskNumber $d.Number -PartitionNumber 1 -AssignDriveLetter
    Start-Sleep -Seconds 2
}
$boot = Get-Partition -DiskNumber $d.Number -PartitionNumber 1 -ErrorAction SilentlyContinue
if ($boot -and $boot.DriveLetter) {
    Write-Host ("      Boot partition drive letter: {0}:" -f $boot.DriveLetter) -ForegroundColor Green
    Get-ChildItem ("{0}:\" -f $boot.DriveLetter) -ErrorAction SilentlyContinue |
        Select-Object Name, Length | Format-Table -AutoSize
}
else {
    Write-Host "      [NOTE] Boot partition has no drive letter, will handle manually later." -ForegroundColor Yellow
}

# --- 5. Read-back verify ---
Write-Host "[4/4] Verifying (first 128MB + last 32MB)..." -ForegroundColor Cyan
function Get-HashOfRange {
    param([string]$dev, [long]$len, [long]$offset)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $f = New-Object System.IO.FileStream($dev, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite, 4096, $false)
    try {
        $f.Position = $offset
        $buf = New-Object byte[] (4 * $MB)
        $left = $len
        while ($left -gt 0) {
            $want = [int][Math]::Min([long]$buf.Length, $left)
            $read = $f.Read($buf, 0, $want)
            if ($read -le 0) { break }
            $sha.TransformBlock($buf, 0, $read, $null, 0) | Out-Null
            $left -= $read
        }
        $sha.TransformFinalBlock((New-Object byte[] 0), 0, 0) | Out-Null
        return [BitConverter]::ToString($sha.Hash).Replace('-', '')
    }
    finally { $f.Close() }
}
function Get-HashOfFile {
    param([string]$path, [long]$len, [long]$offset)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $f = [System.IO.File]::OpenRead($path)
    try {
        $f.Position = $offset
        $buf = New-Object byte[] (4 * $MB)
        $left = $len
        while ($left -gt 0) {
            $want = [int][Math]::Min([long]$buf.Length, $left)
            $read = $f.Read($buf, 0, $want)
            if ($read -le 0) { break }
            $sha.TransformBlock($buf, 0, $read, $null, 0) | Out-Null
            $left -= $read
        }
        $sha.TransformFinalBlock((New-Object byte[] 0), 0, 0) | Out-Null
        return [BitConverter]::ToString($sha.Hash).Replace('-', '')
    }
    finally { $f.Close() }
}

$headLen = 128 * $MB
$tailLen = 32 * $MB
$tailOff = $imgLen - $tailLen

$a = Get-HashOfFile  $img     $headLen 0
$b = Get-HashOfRange $devPath $headLen 0
$c = Get-HashOfFile  $img     $tailLen $tailOff
$e = Get-HashOfRange $devPath $tailLen $tailOff

Write-Host ("      head image={0}" -f $a.Substring(0, 16))
Write-Host ("      head disk ={0}" -f $b.Substring(0, 16))
Write-Host ("      tail image={0}" -f $c.Substring(0, 16))
Write-Host ("      tail disk ={0}" -f $e.Substring(0, 16))
if ($a -eq $b -and $c -eq $e) {
    Write-Host ""
    Write-Host "  [OK] Verify PASSED: disk content matches the image." -ForegroundColor Green
}
else {
    Write-Host ""
    Write-Host "  [FAIL] Verify FAILED: disk content differs. DO NOT use this card." -ForegroundColor Red
    exit 2
}

Write-Host ""
Write-Host "Next: remove card from reader, insert into the Pi, plug LAN cable to router, power on." -ForegroundColor Cyan
Write-Host ""
