#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Initializes this template into a concrete Go module.

.DESCRIPTION
    POSIX counterpart: scripts/init.sh — use whichever matches your shell.

    Replaces the placeholder tokens (__ProjectName__, __GoPackage__, __Author__,
    __AuthorEmail__, __GitHubOwner__, __Description__, __Year__) in file contents
    AND in file/folder names, then removes the template-only files (TEMPLATE.md,
    docs/AGENT-INIT-GUIDE.md, and the disposable initializer test harness) and —
    unless -KeepScript — both initializers, init.ps1 and init.sh. Changes are
    prepared in a staging tree and committed with rollback protection.

    Run it once, right after creating a repository from the template:

        pwsh ./scripts/init.ps1 -ProjectName my-widgets

    Omitted optional values fall back to sensible defaults so the result always
    builds; edit LICENSE / go.mod afterwards if you need to refine them.

.PARAMETER ProjectName
    Project name. Required. Two values are *derived* from it:
      * a module slug (lowercased, runs of non-alphanumerics collapsed to '-',
        leading/trailing '-' trimmed — e.g. "Acme.Widgets" -> "acme-widgets")
        substituted for EVERY __ProjectName__ token: the go.mod module-path
        element, the repository URLs, and any token-named files/folders.
      * a Go package identifier (lowercased, alphanumerics only — e.g.
        "acmewidgets") substituted for __GoPackage__ in the `package` declarations.
    The slug must start with a letter (a leading digit makes a poor import-path
    element / package name); init errors if it does not. Name your GitHub repo
    with the slug, or edit go.mod's module path to match your real remote.

.PARAMETER Author
    Author for LICENSE. Defaults to `git config user.name`, else "Your Name".

.PARAMETER AuthorEmail
    Author email for the release commit. Defaults to `git config user.email`, else "you@example.com".

.PARAMETER GitHubOwner
    GitHub owner/org used in the module path and repository URLs. Defaults to "your-org".

.PARAMETER Description
    Short project description. Defaults to "TODO: project description".

.PARAMETER Year
    Copyright year. Defaults to the current year.

.PARAMETER KeepScript
    Keep both initializers (init.ps1 and init.sh) after running. TEMPLATE.md and
    docs/AGENT-INIT-GUIDE.md and the disposable test harness are removed either way.

.EXAMPLE
    pwsh ./scripts/init.ps1 -ProjectName my-widgets -Author "Jane Doe" -GitHubOwner acme -Description "A small module"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectName,
    [string]$Author,
    [string]$AuthorEmail,
    [string]$GitHubOwner,
    [string]$Description,
    [int]$Year = (Get-Date).Year,
    [switch]$KeepScript
)

$ErrorActionPreference = 'Stop'

# Module slug: lowercase, collapse runs of non-alphanumerics to '-', trim '-'.
$slug = ($ProjectName.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
if (-not $slug) {
    throw "Invalid -ProjectName '$ProjectName'. It must contain at least one ASCII letter or digit (e.g. my-widgets)."
}
if ($slug -notmatch '^[a-z]') {
    throw "Invalid -ProjectName '$ProjectName' -> derived module slug '$slug' starts with a non-letter. Pick a name whose first alphanumeric is a letter (e.g. my-widgets)."
}
# Go package identifier: lowercase, drop every non-alphanumeric.
$goPackage = ($ProjectName.ToLowerInvariant() -replace '[^a-z0-9]+', '')
# Reject a package name Go can't use for a library: any of the 25 reserved
# keywords (a syntax error in `package X`) or "main" (which would make this an
# executable package expecting func main). The slug is unaffected.
$goKeywords = @('break', 'case', 'chan', 'const', 'continue', 'default', 'defer', 'else', 'fallthrough', 'for', 'func', 'go', 'goto', 'if', 'import', 'interface', 'map', 'main', 'package', 'range', 'return', 'select', 'struct', 'switch', 'type', 'var')
if ($goKeywords -contains $goPackage) {
    throw "Invalid -ProjectName '$ProjectName' -> derived Go package name '$goPackage' is a Go keyword (or 'main'), which cannot name a library package. Pick a different project name (e.g. prefix it: 'go-$goPackage')."
}

if (-not $Author) {
    $Author = (& git config user.name 2>$null)
    if (-not $Author) { $Author = 'Your Name' }
}
if (-not $AuthorEmail) {
    $AuthorEmail = (& git config user.email 2>$null)
    if (-not $AuthorEmail) { $AuthorEmail = 'you@example.com' }
}
if (-not $GitHubOwner) { $GitHubOwner = 'your-org' }
if (-not $Description) { $Description = 'TODO: project description' }

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$selfPath = $PSCommandPath
$siblingSh = Join-Path $PSScriptRoot 'init.sh'
$testHarness = Join-Path $PSScriptRoot 'test-init.sh'
$failureStage = $env:TEMPLATE_INIT_FAIL_AT
$parentRoot = Split-Path -Parent $repoRoot
$transactionPrefix = '.' + (Split-Path -Leaf $repoRoot) + '.init-backup'

# Go has no quoted-string manifest fields for these values (go.mod's module path is
# the derived slug; author/description land in plain-text files), so substitution
# uses raw values everywhere — no per-file-type escaping.
$replacements = [ordered]@{
    '__ProjectName__' = $slug
    '__GoPackage__'   = $goPackage
    '__Author__'      = $Author
    '__AuthorEmail__' = $AuthorEmail
    '__GitHubOwner__' = $GitHubOwner
    '__Description__' = $Description
    '__Year__'        = "$Year"
}

# Binary files carry no tokens; reading/rewriting them as text would corrupt them.
$binaryExtensions = @('.png', '.jpg', '.jpeg', '.gif', '.ico', '.zip')
$excludedDirs = @('.git', '.jj', 'vendor')
$excludedTopLevel = $excludedDirs
$runtimeScripts = @('scripts/init.ps1', 'scripts/init.sh', 'scripts/test-init.sh')
$stageRoot = $null
$backupRoot = $null
$swapComplete = $false
$swapStarted = $false
$rollbackComplete = $false
$evacuatedPaths = [System.Collections.Generic.List[string]]::new()
$installedPaths = [System.Collections.Generic.List[string]]::new()

function Fail-At([string]$stage) {
    if ($failureStage -eq $stage) {
        throw "Injected initializer failure at stage '$stage'."
    }
}

function Remove-PathIfPresent([string]$path) {
    if (Test-Path -LiteralPath $path) {
        Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop
    }
}

function Copy-TemplateTree([string]$sourceRoot, [string]$destinationRoot) {
    foreach ($item in (Get-ChildItem -LiteralPath $sourceRoot -Force)) {
        if ($excludedTopLevel -contains $item.Name) { continue }
        Copy-Item -LiteralPath $item.FullName -Destination $destinationRoot -Recurse -Force -ErrorAction Stop
    }
}

function Test-Excluded([string]$root, [string]$fullPath) {
    $relativePath = $fullPath.Substring($root.Length).TrimStart('\', '/')
    foreach ($segment in ($relativePath -split '[\\/]')) {
        if ($excludedDirs -contains $segment) { return $true }
    }
    return $false
}

function Test-RuntimeScript([string]$root, [string]$fullPath) {
    $relativePath = $fullPath.Substring($root.Length).TrimStart('\', '/').Replace('\', '/')
    return $runtimeScripts -contains $relativePath
}

function Restore-UnresolvedBackup {
    $candidates = @(
        Get-ChildItem -LiteralPath $parentRoot -Directory -Force |
            Where-Object { $_.Name.StartsWith($transactionPrefix, [StringComparison]::Ordinal) }
    )
    if ($candidates.Count -gt 1) {
        throw "Found $($candidates.Count) unresolved initializer backups beside '$repoRoot'; refusing to choose one automatically."
    }
    if ($candidates.Count -eq 0) { return }

    $candidate = $candidates[0].FullName
    Write-Host "==> Recovering interrupted rollback from '$candidate'" -ForegroundColor Yellow
    $recoveredPaths = [System.Collections.Generic.List[string]]::new()

    # Ordinary scripts entries are backed up below a scripts container because the
    # live scripts directory itself must remain in place while an initializer runs.
    $savedScripts = Join-Path $candidate 'scripts'
    if (Test-Path -LiteralPath $savedScripts -PathType Container) {
        $liveScripts = Join-Path $repoRoot 'scripts'
        New-Item -ItemType Directory -Path $liveScripts -Force | Out-Null
        foreach ($entry in @(Get-ChildItem -LiteralPath $savedScripts -Force)) {
            $relativePath = 'scripts/' + $entry.Name
            $target = Join-Path $repoRoot $relativePath
            if (Test-Path -LiteralPath $target) {
                throw "Cannot recover '$candidate': restore target '$target' already exists."
            }
            try {
                Move-Item -LiteralPath $entry.FullName -Destination $target -ErrorAction Stop
            }
            catch {
                throw "Cannot recover '$candidate': failed to restore '$relativePath': $($_.Exception.Message)"
            }
            $recoveredPaths.Add($relativePath)
        }
        Remove-Item -LiteralPath $savedScripts -Force -ErrorAction Stop
    }

    foreach ($entry in @(Get-ChildItem -LiteralPath $candidate -Force)) {
        $target = Join-Path $repoRoot $entry.Name
        if (Test-Path -LiteralPath $target) {
            throw "Cannot recover '$candidate': restore target '$target' already exists."
        }
        try {
            Move-Item -LiteralPath $entry.FullName -Destination $repoRoot -ErrorAction Stop
        }
        catch {
            throw "Cannot recover '$candidate': failed to restore '$($entry.Name)': $($_.Exception.Message)"
        }
        $recoveredPaths.Add($entry.Name)
    }

    foreach ($relativePath in $recoveredPaths) {
        if (-not (Test-Path -LiteralPath (Join-Path $repoRoot $relativePath))) {
            throw "Cannot verify restored entry '$relativePath'; backup remains at '$candidate'."
        }
    }
    if (Get-ChildItem -LiteralPath $candidate -Force) {
        throw "Cannot verify that recovery backup '$candidate' is empty."
    }
    Remove-Item -LiteralPath $candidate -Force -ErrorAction Stop
}

function Rollback-Swap {
    foreach ($relativePath in $installedPaths) {
        $installed = Join-Path $repoRoot $relativePath
        Remove-PathIfPresent $installed
        if (Test-Path -LiteralPath $installed) {
            throw "Rollback could not remove installed entry '$installed'."
        }
    }

    $restored = 0
    foreach ($relativePath in $evacuatedPaths) {
        $saved = Join-Path $backupRoot $relativePath
        $target = Join-Path $repoRoot $relativePath
        if (-not (Test-Path -LiteralPath $saved)) {
            throw "Rollback backup entry is missing: '$saved'."
        }
        if (Test-Path -LiteralPath $target) {
            throw "Rollback restore target already exists: '$target'."
        }
        $targetParent = Split-Path -Parent $target
        New-Item -ItemType Directory -Path $targetParent -Force | Out-Null
        Move-Item -LiteralPath $saved -Destination $target -ErrorAction Stop
        $restored++
        if ($failureStage -eq 'restore' -and $restored -eq 1) {
            throw "Injected initializer failure at stage 'restore'."
        }
    }

    foreach ($relativePath in $evacuatedPaths) {
        if ((Test-Path -LiteralPath (Join-Path $backupRoot $relativePath)) -or
            -not (Test-Path -LiteralPath (Join-Path $repoRoot $relativePath))) {
            throw "Rollback could not verify restored entry '$relativePath'."
        }
    }
}

function Apply-ScriptsStage {
    $liveScripts = Join-Path $repoRoot 'scripts'
    $stagedScripts = Join-Path $stageRoot 'scripts'
    $savedScripts = Join-Path $backupRoot 'scripts'
    $runtimeNames = @('init.ps1', 'init.sh', 'test-init.sh')
    $scriptEvacuations = 0
    $scriptInstalls = 0

    New-Item -ItemType Directory -Path $liveScripts -Force | Out-Null
    New-Item -ItemType Directory -Path $savedScripts -Force | Out-Null

    # Keep the live directory and runtime scripts in place. Only ordinary direct
    # children move; a token-named directory carries its transformed descendants.
    foreach ($entry in @(Get-ChildItem -LiteralPath $liveScripts -Force)) {
        if ($runtimeNames -contains $entry.Name) { continue }
        $relativePath = 'scripts/' + $entry.Name
        $savedPath = Join-Path $backupRoot $relativePath
        Move-Item -LiteralPath $entry.FullName -Destination $savedPath -ErrorAction Stop
        $evacuatedPaths.Add($relativePath)
        $scriptEvacuations++
        if ($failureStage -eq 'remove-scripts' -and $scriptEvacuations -eq 1) {
            throw "Injected initializer failure at stage 'remove-scripts'."
        }
    }

    foreach ($entry in @(Get-ChildItem -LiteralPath $stagedScripts -Force)) {
        if ($runtimeNames -contains $entry.Name) { continue }
        $relativePath = 'scripts/' + $entry.Name
        $targetPath = Join-Path $repoRoot $relativePath
        if (Test-Path -LiteralPath $targetPath) {
            throw "Cannot install staged script entry '$relativePath': target '$targetPath' already exists."
        }
        Move-Item -LiteralPath $entry.FullName -Destination $targetPath -ErrorAction Stop
        $installedPaths.Add($relativePath)
        $scriptInstalls++
        if ($failureStage -eq 'scripts' -and $scriptInstalls -eq 1) {
            throw "Injected initializer failure at stage 'scripts'."
        }
    }
}

Write-Host "==> Initializing template as '$slug' (package '$goPackage')" -ForegroundColor Cyan

try {
    Restore-UnresolvedBackup

    # Prepare every change outside the live tree. The stage is adjacent to the
    # repository so the final moves stay on one filesystem and can be rolled back.
    $stageRoot = Join-Path $parentRoot ('.' + (Split-Path -Leaf $repoRoot) + '.init-stage-' + [guid]::NewGuid().ToString('N'))
    $backupRoot = Join-Path $parentRoot ('.' + (Split-Path -Leaf $repoRoot) + '.init-backup-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
    Copy-TemplateTree $repoRoot $stageRoot
    Fail-At 'copy'

    # Binary files are never decoded. Runtime scripts are staged byte-for-byte and
    # stay untouched until final cleanup.
    $files = Get-ChildItem -Path $stageRoot -File -Recurse -Force | Where-Object {
        -not (Test-Excluded $stageRoot $_.FullName) -and
        -not (Test-RuntimeScript $stageRoot $_.FullName)
    }
    $contentChanged = 0
    foreach ($file in $files) {
        if ($binaryExtensions -contains $file.Extension) { continue }
        $text = [System.IO.File]::ReadAllText($file.FullName)
        $new = $text
        foreach ($key in $replacements.Keys) {
            $new = $new.Replace($key, $replacements[$key])
        }
        if ($new -ne $text) {
            # UTF-8 without BOM, LF preserved — matches .gitattributes (eol=lf).
            [System.IO.File]::WriteAllText($file.FullName, $new, (New-Object System.Text.UTF8Encoding($false)))
            $contentChanged++
        }
    }
    Write-Host "    Updated contents in $contentChanged file(s)." -ForegroundColor DarkGray
    Fail-At 'content'

    # Rename deepest paths first so child renames do not invalidate parent paths.
    $named = Get-ChildItem -Path $stageRoot -Recurse -Force | Where-Object {
        -not (Test-Excluded $stageRoot $_.FullName) -and
        -not (Test-RuntimeScript $stageRoot $_.FullName) -and
        $_.Name -like '*__ProjectName__*'
    } | Sort-Object { $_.FullName.Length } -Descending
    foreach ($item in $named) {
        $newName = $item.Name.Replace('__ProjectName__', $slug)
        Rename-Item -LiteralPath $item.FullName -NewName $newName -ErrorAction Stop
        Write-Host "    Renamed $($item.Name) -> $newName" -ForegroundColor DarkGray
    }
    Fail-At 'rename'

    # Activate Claude Code shared settings in the staged tree.
    $claudeTemplate = Join-Path $stageRoot '.claude/settings.json.template'
    if (Test-Path -LiteralPath $claudeTemplate) {
        Move-Item -LiteralPath $claudeTemplate -Destination (Join-Path $stageRoot '.claude/settings.json') -Force -ErrorAction Stop
        Write-Host "    Activated .claude/settings.json" -ForegroundColor DarkGray
    }
    Fail-At 'activate'

    # Remove template-only files in the staged tree. A failure here cannot affect
    # the source tree and the complete operation can be retried unchanged.
    foreach ($rel in @('TEMPLATE.md', 'docs/AGENT-INIT-GUIDE.md')) {
        Remove-PathIfPresent (Join-Path $stageRoot $rel)
    }
    $stagedDocs = Join-Path $stageRoot 'docs'
    if ((Test-Path -LiteralPath $stagedDocs) -and -not (Get-ChildItem -LiteralPath $stagedDocs -Force)) {
        Remove-Item -LiteralPath $stagedDocs -Force -ErrorAction Stop
    }
    Fail-At 'delete'

    # Swap only mutable top-level entries. scripts/ is applied separately so its
    # live directory and runtime files never move while an initializer runs.
    $originalPaths = @(
        Get-ChildItem -LiteralPath $repoRoot -Force |
            Where-Object { $excludedTopLevel -notcontains $_.Name -and $_.Name -ne 'scripts' } |
            Select-Object -ExpandProperty Name
    )
    $stagedPaths = @(
        Get-ChildItem -LiteralPath $stageRoot -Force |
            Where-Object { $_.Name -ne 'scripts' } |
            Select-Object -ExpandProperty Name
    )
    New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
    $swapStarted = $true
    foreach ($relativePath in $originalPaths) {
        $backupPath = Join-Path $backupRoot $relativePath
        New-Item -ItemType Directory -Path (Split-Path -Parent $backupPath) -Force | Out-Null
        Move-Item -LiteralPath (Join-Path $repoRoot $relativePath) -Destination $backupPath -Force -ErrorAction Stop
        $evacuatedPaths.Add($relativePath)
        if ($failureStage -eq 'evacuate' -and $evacuatedPaths.Count -eq 1) {
            throw "Injected initializer failure at stage 'evacuate'."
        }
    }
    $stagedMoves = 0
    foreach ($relativePath in $stagedPaths) {
        $targetPath = Join-Path $repoRoot $relativePath
        New-Item -ItemType Directory -Path (Split-Path -Parent $targetPath) -Force | Out-Null
        Move-Item -LiteralPath (Join-Path $stageRoot $relativePath) -Destination $targetPath -Force -ErrorAction Stop
        $installedPaths.Add($relativePath)
        $stagedMoves++
        if (($failureStage -eq 'commit' -or $failureStage -eq 'restore') -and $stagedMoves -eq 1) {
            throw "Injected initializer failure at stage '$failureStage'."
        }
    }
    Apply-ScriptsStage
    $swapComplete = $true

    Write-Host ""
    Write-Host "Done. Next steps:" -ForegroundColor Green
    Write-Host "  1. go build ./... && go test ./..."
    Write-Host "  2. gofmt -w . && go vet ./..."
    Write-Host "  3. Review LICENSE (author/year) and the module path in go.mod."
    Write-Host "  4. Replace greeter.go (and greeter_test.go) with your real API."
    Write-Host "  5. Releasing: push a vX.Y.Z tag — no secret needed (proxy.golang.org and"
    Write-Host "     pkg.go.dev pick it up). Delete .github/workflows/release.yml if not publishing."
    Write-Host "  6. Fill the Architecture section of CLAUDE.md, then commit."

    # These are the only live-tree deletions. They happen after the swap, so a
    # locked file leaves a complete initialized tree that is safe to retry.
    if (-not $KeepScript) {
        if (Test-Path -LiteralPath $testHarness) { Remove-Item -LiteralPath $testHarness -Force -ErrorAction Stop }
        if (Test-Path -LiteralPath $siblingSh) { Remove-Item -LiteralPath $siblingSh -Force -ErrorAction Stop }
        Remove-Item -LiteralPath $selfPath -Force -ErrorAction Stop
    } elseif (Test-Path -LiteralPath $testHarness) {
        Remove-Item -LiteralPath $testHarness -Force -ErrorAction Stop
    }
}
catch {
    $initialFailure = $_
    if (-not $swapComplete -and $swapStarted) {
        try {
            Rollback-Swap
            $rollbackComplete = $true
        }
        catch {
            throw "Initializer failed: $($initialFailure.Exception.Message) Rollback also failed: $($_.Exception.Message) Original entries remain recoverable at '$backupRoot'."
        }
    }
    throw $initialFailure
}
finally {
    if ($stageRoot) { Remove-PathIfPresent $stageRoot }
    if ($backupRoot -and (Test-Path -LiteralPath $backupRoot)) {
        if (-not $swapStarted -or $swapComplete -or $rollbackComplete) {
            Remove-PathIfPresent $backupRoot
        } else {
            Write-Warning "Preserving incomplete rollback backup at '$backupRoot'."
        }
    }
}
