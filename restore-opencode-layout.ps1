param(
    [Parameter(Position = 0)]
    [string]$OpenCodePath
)

$ErrorActionPreference = 'Stop'

$PatchId = 'opencode-layout-swap-patch'

function Add-AppAsarCandidate {
    param(
        [System.Collections.Generic.List[string]]$List,
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { return }

    $p = [Environment]::ExpandEnvironmentVariables($Path.Trim().Trim('"'))

    if ($p -match '(?i)app\.asar$') {
        [void]$List.Add($p)
        return
    }

    if ($p -match '(?i)\.exe$') {
        $p = Split-Path -Parent $p
    }

    [void]$List.Add((Join-Path $p 'resources\app.asar'))
}

function Resolve-AppAsar {
    param([string]$Hint)

    $candidates = [System.Collections.Generic.List[string]]::new()

    Add-AppAsarCandidate $candidates $Hint

    if ($env:LOCALAPPDATA) {
        Add-AppAsarCandidate $candidates (Join-Path $env:LOCALAPPDATA 'Programs\OpenCode')
        Add-AppAsarCandidate $candidates (Join-Path $env:LOCALAPPDATA 'Programs\opencode')
        Add-AppAsarCandidate $candidates (Join-Path $env:LOCALAPPDATA 'OpenCode')
    }

    $cmd = Get-Command 'OpenCode.exe' -ErrorAction SilentlyContinue
    if ($cmd) { Add-AppAsarCandidate $candidates $cmd.Source }

    $uninstallRoots = @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    foreach ($root in $uninstallRoots) {
        $apps = Get-ItemProperty $root -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -and $_.DisplayName -match '(?i)^OpenCode(?:\s|$)' }
        foreach ($app in $apps) {
            if ($app.InstallLocation) { Add-AppAsarCandidate $candidates $app.InstallLocation }
            if ($app.DisplayIcon) {
                $iconPath = ($app.DisplayIcon -replace ',\s*\d+\s*$', '').Trim().Trim('"')
                Add-AppAsarCandidate $candidates $iconPath
            }
        }
    }

    $seen = @{}
    foreach ($candidate in $candidates) {
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        $full = [System.IO.Path]::GetFullPath($candidate)
        $key = $full.ToLowerInvariant()
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        if (Test-Path -LiteralPath $full -PathType Leaf) { return $full }
    }

    if ($env:LOCALAPPDATA) {
        $programs = Join-Path $env:LOCALAPPDATA 'Programs'
        if (Test-Path -LiteralPath $programs -PathType Container) {
            $hit = Get-ChildItem -LiteralPath $programs -Filter 'app.asar' -File -Recurse -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -match '(?i)\\opencode[^\\]*\\resources\\app\.asar$' } |
                Select-Object -First 1
            if ($hit) { return $hit.FullName }
        }
    }

    Write-Host ''
    Write-Host 'OpenCode app.asar was not found automatically.' -ForegroundColor Yellow
    $manual = Read-Host 'Enter OpenCode install directory, OpenCode.exe, or app.asar path'
    if (-not [string]::IsNullOrWhiteSpace($manual)) {
        $manualList = [System.Collections.Generic.List[string]]::new()
        Add-AppAsarCandidate $manualList $manual
        foreach ($candidate in $manualList) {
            if (Test-Path -LiteralPath $candidate -PathType Leaf) { return [System.IO.Path]::GetFullPath($candidate) }
        }
    }

    throw 'Cannot locate OpenCode resources\app.asar.'
}

function Ensure-OpenCodeStopped {
    param([string]$AsarPath)
    $resourcesDir = Split-Path -Parent $AsarPath
    $installDir = Split-Path -Parent $resourcesDir
    $running = @()
    foreach ($p in Get-Process -ErrorAction SilentlyContinue) {
        try {
            if ($p.Path -and $p.Path.StartsWith($installDir, [System.StringComparison]::OrdinalIgnoreCase)) { $running += $p }
        } catch { }
    }
    if ($running.Count -eq 0) { return }
    Write-Host ''
    Write-Host 'OpenCode is currently running.' -ForegroundColor Yellow
    $answer = Read-Host 'Close OpenCode now? [Y/N]'
    if ($answer -notmatch '^(?i:y|yes)$') { throw 'Restore cancelled. Close OpenCode and run the script again.' }
    $running | Stop-Process -Force
    Start-Sleep -Milliseconds 800
}

function Invoke-NativeCaptured {
    param([string]$Executable,[string[]]$Arguments)
    $oldPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $nativeOutput = @(& $Executable @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    } finally { $ErrorActionPreference = $oldPreference }
    $text = ($nativeOutput | ForEach-Object { "$_" }) -join [Environment]::NewLine
    return [pscustomobject]@{ ExitCode = $exitCode; Output = $text }
}

function Resolve-AsarRunner {
    $npx = Get-Command 'npx.cmd' -ErrorAction SilentlyContinue
    if (-not $npx) { $npx = Get-Command 'npx' -ErrorAction SilentlyContinue }
    if ($npx) {
        foreach ($pkg in @('@electron/asar@3.2.17', '@electron/asar')) {
            $probe = Invoke-NativeCaptured -Executable $npx.Source -Arguments @('--yes', $pkg, '--version')
            if ($probe.ExitCode -eq 0) { return [pscustomobject]@{ Type = 'npx'; Path = $npx.Source; Package = $pkg } }
        }
    }
    $bunx = Get-Command 'bunx.exe' -ErrorAction SilentlyContinue
    if (-not $bunx) { $bunx = Get-Command 'bunx' -ErrorAction SilentlyContinue }
    if ($bunx) {
        foreach ($pkg in @('@electron/asar@3.2.17', '@electron/asar')) {
            $probe = Invoke-NativeCaptured -Executable $bunx.Source -Arguments @($pkg, '--version')
            if ($probe.ExitCode -eq 0) { return [pscustomobject]@{ Type = 'bunx'; Path = $bunx.Source; Package = $pkg } }
        }
    }
    throw 'No usable ASAR CLI was found. Install Node.js/npm (npx) or Bun (bunx), then run again.'
}

function Invoke-Asar {
    param([pscustomobject]$Runner,[string[]]$CommandArgs)
    if ($Runner.Type -eq 'npx') { $args = @('--yes', $Runner.Package) + $CommandArgs } else { $args = @($Runner.Package) + $CommandArgs }
    $result = Invoke-NativeCaptured -Executable $Runner.Path -Arguments $args
    if ($result.ExitCode -ne 0) {
        $detail = if ([string]::IsNullOrWhiteSpace($result.Output)) { '(no output)' } else { $result.Output }
        throw "ASAR command failed (exit $($result.ExitCode)): $($CommandArgs -join ' ')`r`n$detail"
    }
}

function Find-RendererIndex {
    param([string]$ExtractedRoot)
    $expected = Join-Path $ExtractedRoot 'out\renderer\index.html'
    if (Test-Path -LiteralPath $expected -PathType Leaf) { return $expected }
    foreach ($file in Get-ChildItem -LiteralPath $ExtractedRoot -Filter 'index.html' -File -Recurse -ErrorAction SilentlyContinue) {
        try {
            $text = [System.IO.File]::ReadAllText($file.FullName)
            if ($text -match '<div\s+id=["'']root["'']' -and $text -match '(?i)OpenCode') { return $file.FullName }
        } catch { }
    }
    throw 'Could not find the OpenCode renderer index.html inside app.asar.'
}

$workDir = $null
$newAsar = $null

try {
    $asarPath = Resolve-AppAsar $OpenCodePath
    Write-Host "OpenCode app.asar: $asarPath" -ForegroundColor Cyan
    Ensure-OpenCodeStopped $asarPath
    Write-Host 'Resolving ASAR tool...'
    $runner = Resolve-AsarRunner
    Write-Host "Using $($runner.Type): $($runner.Package)"
    $workDir = Join-Path $env:TEMP ('opencode-layout-restore-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $workDir | Out-Null
    Write-Host 'Extracting app.asar...'
    Invoke-Asar -Runner $runner -CommandArgs @('extract', $asarPath, $workDir)

    $originalUnpacked = "$asarPath.unpacked"
    $unpackTopDirs = @(); $unpackTopFiles = @()
    if (Test-Path -LiteralPath $originalUnpacked -PathType Container) {
        Write-Host 'Preserving app.asar.unpacked entries...'
        foreach ($item in Get-ChildItem -LiteralPath $originalUnpacked -Force -ErrorAction SilentlyContinue) {
            Copy-Item -LiteralPath $item.FullName -Destination $workDir -Recurse -Force
            if ($item.PSIsContainer) { $unpackTopDirs += $item.Name } else { $unpackTopFiles += $item.Name }
        }
    }

    $indexPath = Find-RendererIndex $workDir
    Write-Host "Renderer: $indexPath"
    $html = [System.IO.File]::ReadAllText($indexPath)
    $patchPattern = '(?is)\s*<style\s+id="' + [regex]::Escape($PatchId) + '"[^>]*>.*?</style>\s*'
    $patchRegex = [System.Text.RegularExpressions.Regex]::new($patchPattern)
    if (-not $patchRegex.IsMatch($html)) {
        Write-Host ''
        Write-Host 'NO PATCH FOUND' -ForegroundColor Yellow
        Write-Host 'The current OpenCode app.asar already appears to use the stock layout.'
        exit 0
    }
    $html = $patchRegex.Replace($html, "`r`n")
    [System.IO.File]::WriteAllText($indexPath, $html, [System.Text.UTF8Encoding]::new($false))

    $newAsar = "$asarPath.layout-new"
    Remove-Item -LiteralPath $newAsar -Force -ErrorAction SilentlyContinue
    Write-Host 'Packing restored app.asar...'
    $packArgs = @('pack', $workDir, $newAsar)
    if ($unpackTopDirs.Count -gt 0) {
        $dirGlob = if ($unpackTopDirs.Count -eq 1) { $unpackTopDirs[0] } else { '{' + ($unpackTopDirs -join ',') + '}' }
        $packArgs += @('--unpack-dir', $dirGlob)
    }
    if ($unpackTopFiles.Count -gt 0) {
        $fileGlob = if ($unpackTopFiles.Count -eq 1) { $unpackTopFiles[0] } else { '{' + ($unpackTopFiles -join ',') + '}' }
        $packArgs += @('--unpack', $fileGlob)
    }
    Invoke-Asar -Runner $runner -CommandArgs $packArgs
    if (-not (Test-Path -LiteralPath $newAsar -PathType Leaf)) { throw 'Restored app.asar was not created.' }
    if ((Get-Item -LiteralPath $newAsar).Length -lt 1MB) { throw 'Restored app.asar looks unexpectedly small; refusing to replace the current file.' }

    $newUnpacked = "$newAsar.unpacked"
    if (Test-Path -LiteralPath $newUnpacked -PathType Container) {
        if (-not (Test-Path -LiteralPath $originalUnpacked -PathType Container)) { New-Item -ItemType Directory -Path $originalUnpacked | Out-Null }
        foreach ($item in Get-ChildItem -LiteralPath $newUnpacked -Force -ErrorAction SilentlyContinue) {
            Copy-Item -LiteralPath $item.FullName -Destination $originalUnpacked -Recurse -Force
        }
    }
    Copy-Item -LiteralPath $newAsar -Destination $asarPath -Force
    Write-Host ''
    Write-Host 'RESTORE SUCCESSFUL' -ForegroundColor Green
    Write-Host 'The injected layout CSS was removed. OpenCode is back to its stock layout.'
}
catch {
    Write-Host ''
    Write-Host 'RESTORE FAILED' -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
finally {
    if ($newAsar -and (Test-Path -LiteralPath $newAsar)) { Remove-Item -LiteralPath $newAsar -Force -ErrorAction SilentlyContinue }
    if ($newAsar -and (Test-Path -LiteralPath "$newAsar.unpacked")) { Remove-Item -LiteralPath "$newAsar.unpacked" -Recurse -Force -ErrorAction SilentlyContinue }
    if ($workDir -and (Test-Path -LiteralPath $workDir)) { Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue }
}
