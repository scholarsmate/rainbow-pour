param(
	[string]$Package = "com.davinshearer.rainbowhanoi",
	[string]$OutDir = "logs/android",
	[switch]$Launch,
	[switch]$Snapshot,
	[switch]$NoClear
)

$ErrorActionPreference = "Stop"

$adb = Join-Path $env:LOCALAPPDATA "Android\Sdk\platform-tools\adb.exe"
if (-not (Test-Path $adb)) {
	$adb = "adb"
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$fullLog = Join-Path $OutDir "rainbow-hanoi-$stamp-full.log"
$focusedLog = Join-Path $OutDir "rainbow-hanoi-$stamp-focused.log"
$packagePattern = [regex]::Escape($Package)
$pattern = "($packagePattern|Godot|godot|AndroidRuntime|FATAL EXCEPTION|Fatal signal|SIGSEGV|SIGABRT|libgodot|tombstone|lowmemorykiller|lmkd|am_kill|OutOfMemory|ANR)"

Write-Host "Checking connected devices..."
& $adb devices

if (-not $NoClear) {
	Write-Host "Clearing logcat buffer..."
	& $adb logcat -c
}

if ($Launch) {
	Write-Host "Launching $Package..."
	& $adb shell monkey -p $Package -c android.intent.category.LAUNCHER 1 | Out-Host
	Start-Sleep -Seconds 1
}

Write-Host "Full log:    $fullLog"
Write-Host "Focused log: $focusedLog"

if ($Snapshot) {
	& $adb logcat -d -v time |
		Tee-Object -FilePath $fullLog |
		Select-String -Pattern $pattern |
		Tee-Object -FilePath $focusedLog
	Write-Host "Snapshot complete."
	exit 0
}

Write-Host "Capturing logcat. Reproduce the crash, then press Ctrl+C here."
& $adb logcat -v time |
	Tee-Object -FilePath $fullLog |
	Select-String -Pattern $pattern |
	Tee-Object -FilePath $focusedLog
