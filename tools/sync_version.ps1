param(
	[string]$VersionFile = ""
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
if ($VersionFile -eq "") {
	$VersionFile = Join-Path $repoRoot "VERSION.txt"
}
$versionPath = Resolve-Path $VersionFile
$version = ([System.IO.File]::ReadAllText($versionPath)).Trim()

if ($version -notmatch '^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$') {
	throw "VERSION.txt must contain a semantic version like 0.1.0. Found '$version'."
}

function Write-Utf8NoBom([string]$Path, [string]$Text) {
	$encoding = [System.Text.UTF8Encoding]::new($false)
	[System.IO.File]::WriteAllText($Path, $Text, $encoding)
}

function Set-LineValue([string]$Text, [string]$Pattern, [string]$Replacement) {
	if ($Text -match $Pattern) {
		return [regex]::Replace($Text, $Pattern, $Replacement, 1)
	}
	return $Text
}

$projectPath = Join-Path $repoRoot "project.godot"
$projectText = [System.IO.File]::ReadAllText($projectPath)
$projectVersionLine = "config/version=`"$version`""

if ($projectText -match '(?m)^config/version=.*$') {
	$projectText = Set-LineValue $projectText '(?m)^config/version=.*$' $projectVersionLine
} else {
	$newline = if ($projectText.Contains("`r`n")) { "`r`n" } else { "`n" }
	$projectText = [regex]::Replace($projectText, '(?m)^config/description=.*$', {
		param($match)
		"$($match.Value)$newline$projectVersionLine"
	}, 1)
}
Write-Utf8NoBom $projectPath $projectText

$presetPath = Join-Path $repoRoot "export_presets.cfg"
if (Test-Path -LiteralPath $presetPath) {
	$presetText = [System.IO.File]::ReadAllText($presetPath)
	$androidVersionLine = "version/name=`"$version`""
	if ($presetText -match '(?m)^version/name=.*$') {
		$presetText = Set-LineValue $presetText '(?m)^version/name=.*$' $androidVersionLine
	} else {
		$newline = if ($presetText.Contains("`r`n")) { "`r`n" } else { "`n" }
		$presetText = [regex]::Replace($presetText, '(?m)^version/code=.*$', {
			param($match)
			"$($match.Value)$newline$androidVersionLine"
		}, 1)
	}
	Write-Utf8NoBom $presetPath $presetText
}

Write-Host "Synced version $version"
