param(
	[string]$GamePack = "",
	[string]$PatchPack = "",
	[string]$Output = ""
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$projectText = [IO.File]::ReadAllText((Join-Path $projectRoot "project.godot"), [Text.Encoding]::UTF8)
if ($projectText -notmatch '(?m)^config/name="([^"]+)"$') {
	throw "Could not read config/name from project.godot."
}
$appDataName = $Matches[1] -replace '[<>:"/\\|?*]', '-'
$userData = Join-Path $env:APPDATA ("Godot\app_userdata\" + $appDataName)

if ($GamePack -eq "") {
	$GamePack = Join-Path $env:LOCALAPPDATA "Programs\CardWars\CardWars.pck"
}
if ($Output -eq "") {
	$Output = Join-Path $userData "dev_assets_clean.pck"
}
if (-not [IO.File]::Exists($GamePack)) {
	throw "Game pack not found: $GamePack"
}

$updateStatePath = Join-Path $userData "update\state.json"
$updateDir = Join-Path $userData "update"
$sourcePacks = New-Object System.Collections.Generic.List[string]
$sourcePacks.Add($GamePack)
if ($PatchPack -ne "") {
	$sourcePacks.Add($PatchPack)
} elseif ([IO.File]::Exists($updateStatePath)) {
	$state = Get-Content $updateStatePath -Raw -Encoding UTF8 | ConvertFrom-Json
	foreach ($part in @("full", "patch")) {
		$update = $state.$part
		if ($null -ne $update -and $update.file) {
			$path = Join-Path $updateDir $update.file
			if ([IO.File]::Exists($path)) {
				$sourcePacks.Add($path)
			}
		}
	}
}

$entries = @{}
$header = $null
foreach ($sourcePath in $sourcePacks) {
	$source = [IO.File]::OpenRead($sourcePath)
	try {
		$reader = New-Object IO.BinaryReader($source)
		$header = $reader.ReadBytes(112)
		if ([Text.Encoding]::ASCII.GetString($header, 0, 4) -ne "GDPC") {
			throw "Not a Godot PCK: $sourcePath"
		}
		$source.Position = 24
		$fileBase = $reader.ReadUInt64()
		$directoryOffset = $reader.ReadUInt64()
		$source.Position = $directoryOffset
		$count = $reader.ReadUInt32()
		for ($i = 0; $i -lt $count; $i++) {
			$nameLength = $reader.ReadUInt32()
			$name = [Text.Encoding]::UTF8.GetString($reader.ReadBytes($nameLength)).TrimEnd([char]0)
			$offset = $reader.ReadUInt64()
			$size = $reader.ReadUInt64()
			$md5 = $reader.ReadBytes(16)
			$flags = $reader.ReadUInt32()
			$isAsset = $name.StartsWith("assets/") -or $name.StartsWith("card_backs/") `
				-or $name.StartsWith(".godot/imported/") `
				-or ($name.StartsWith(".godot/exported/") -and $name -match '-(display_font|ui_font)\.res$')
			if ($isAsset) {
				$entries[$name] = [pscustomobject]@{
					SourcePath = $sourcePath
					DataOffset = $fileBase + $offset
					Size = $size
					Md5 = $md5
					Flags = $flags
				}
			}
		}
	} finally {
		$source.Dispose()
	}
}

if ($entries.Count -eq 0) {
	throw "No asset entries found in the selected PCK files."
}

$outputDir = Split-Path -Parent $Output
if (-not [IO.Directory]::Exists($outputDir)) {
	[IO.Directory]::CreateDirectory($outputDir) | Out-Null
}
$tempOutput = $Output + ".tmp"
$buffer = New-Object byte[] (1024 * 1024)
$writerStream = [IO.File]::Open($tempOutput, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::None)
try {
	$writer = New-Object IO.BinaryWriter($writerStream)
	$writer.Write($header)
	$writerStream.Position = 24
	$writer.Write([UInt64]112)
	$writer.Write([UInt64]0)
	$writerStream.Position = 112

	$directoryEntries = New-Object System.Collections.Generic.List[object]
	foreach ($name in ($entries.Keys | Sort-Object)) {
		while (($writerStream.Position % 8) -ne 0) {
			$writer.Write([byte]0)
		}
		$item = $entries[$name]
		$destinationOffset = [UInt64]($writerStream.Position - 112)
		$source = [IO.File]::OpenRead($item.SourcePath)
		try {
			$source.Position = [Int64]$item.DataOffset
			$remaining = [Int64]$item.Size
			while ($remaining -gt 0) {
				$read = $source.Read($buffer, 0, [int][Math]::Min($buffer.Length, $remaining))
				if ($read -le 0) {
					throw "Unexpected end of file while copying $name from $($item.SourcePath)."
				}
				$writer.Write($buffer, 0, $read)
				$remaining -= $read
			}
		} finally {
			$source.Dispose()
		}
		$directoryEntries.Add([pscustomobject]@{
			Name = $name
			Offset = $destinationOffset
			Size = [UInt64]$item.Size
			Md5 = $item.Md5
			Flags = $item.Flags
		})
	}

	while (($writerStream.Position % 8) -ne 0) {
		$writer.Write([byte]0)
	}
	$directoryOffset = [UInt64]$writerStream.Position
	$writer.Write([UInt32]$directoryEntries.Count)
	foreach ($entry in $directoryEntries) {
		$nameBytes = [Text.Encoding]::UTF8.GetBytes($entry.Name + [char]0)
		$writer.Write([UInt32]$nameBytes.Length)
		$writer.Write($nameBytes)
		$writer.Write([UInt64]$entry.Offset)
		$writer.Write([UInt64]$entry.Size)
		$writer.Write([byte[]]$entry.Md5)
		$writer.Write([UInt32]$entry.Flags)
	}
	$writerStream.Position = 32
	$writer.Write([UInt64]$directoryOffset)
	$writer.Flush()
} finally {
	$writerStream.Dispose()
}

Move-Item -LiteralPath $tempOutput -Destination $Output -Force
Write-Output ("Wrote {0} entries ({1:N1} MB) to {2}" -f $entries.Count, ((Get-Item $Output).Length / 1MB), $Output)
