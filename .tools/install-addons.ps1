# Copies this EllesmereUI checkout into WoW's AddOns folder.
# The repo root is the EllesmereUI addon; every EllesmereUI* folder inside it
# is its own addon and goes to its own AddOns folder. Each folder is mirrored
# (robocopy /MIR): files that are not in the repo are removed from the copy.
# Libs\ folders are left alone on both sides: the repo has none (the packager
# fetches them, see .pkgmeta), so the ones from your installed release stay.
# Saved settings live under WTF\ and are never touched.
#
# Usage (elevated PowerShell, since AddOns is under Program Files):
#   .\.tools\install-addons.ps1           # copy once
#   .\.tools\install-addons.ps1 -Watch    # copy, then again on every change; /reload in game
#   .\.tools\install-addons.ps1 -AddOns "D:\Games\World of Warcraft\_retail_\Interface\AddOns"

param(
    [string]$AddOns = "C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns",
    [switch]$Watch
)

$ErrorActionPreference = "Stop"
$Source = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

if (-not (Test-Path (Join-Path $Source "EllesmereUI.toc"))) {
    throw "No EllesmereUI.toc in '$Source'."
}
if (-not (Test-Path $AddOns)) {
    throw "AddOns folder not found: '$AddOns'. Pass -AddOns with your WoW path."
}
if (-not (Test-Path (Join-Path $AddOns "EllesmereUI\Libs"))) {
    throw "No EllesmereUI\Libs in '$AddOns'. Install the released EllesmereUI once first: this script keeps its Libs folders."
}

function Mirror($from, $to, $excludeDirs) {
    $rcArgs = @($from, $to, "/MIR", "/NFL", "/NDL", "/NJH", "/NJS", "/NP",
                "/XD") + $excludeDirs + @("/XF", ".gitignore", ".gitattributes")
    & robocopy @rcArgs | Out-Null
    # robocopy: 0-7 is success, 8+ is failure.
    if ($LASTEXITCODE -ge 8) { throw "robocopy failed ($LASTEXITCODE): $from -> $to" }
}

function Install {
    $modules = Get-ChildItem -Path $Source -Directory -Filter "EllesmereUI*"
    # Core addon: the repo root minus the module folders and repo tooling.
    $skip = @(".git", ".github", ".tools", "Libs") + ($modules | ForEach-Object { $_.FullName })
    Mirror $Source (Join-Path $AddOns "EllesmereUI") $skip
    foreach ($m in $modules) {
        Mirror $m.FullName (Join-Path $AddOns $m.Name) @(".git", "Libs")
    }
    Write-Host ("[{0:HH:mm:ss}] Copied {1} addon folders to {2}" -f (Get-Date), ($modules.Count + 1), $AddOns)
}

Install
if (-not $Watch) {
    Write-Host "Done. /reload in game (restart WoW if a new addon folder was added)."
    return
}

# Watch mode: a burst of saves (or a git checkout) copies once, half a
# second after the last change.
$watcher = New-Object System.IO.FileSystemWatcher $Source
$watcher.IncludeSubdirectories = $true
$watcher.NotifyFilter = [System.IO.NotifyFilters]"FileName, DirectoryName, LastWrite"
$watcher.EnableRaisingEvents = $true
$sourceId = "EllesmereUIInstall"
foreach ($ev in "Changed", "Created", "Deleted", "Renamed") {
    Register-ObjectEvent $watcher $ev -SourceIdentifier "$sourceId.$ev" | Out-Null
}
Write-Host "Watching $Source. Ctrl+C to stop."
try {
    while ($true) {
        $e = Wait-Event -Timeout 1
        if (-not $e) { continue }
        $path = $e.SourceEventArgs.FullPath
        Remove-Event -EventIdentifier $e.EventIdentifier
        if ($path -match '\\\.git(\\|$)') { continue }
        # Debounce: drain events until things are quiet.
        do {
            Start-Sleep -Milliseconds 500
            $more = @(Get-Event)
            $more | ForEach-Object { Remove-Event -EventIdentifier $_.EventIdentifier }
        } while ($more.Count -gt 0)
        try { Install } catch { Write-Warning $_ }
    }
} finally {
    Get-EventSubscriber | Where-Object { $_.SourceIdentifier -like "$sourceId.*" } | Unregister-Event
    $watcher.Dispose()
}
