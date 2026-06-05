#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Initializes this template into a concrete Go module.

.DESCRIPTION
    POSIX counterpart: scripts/init.sh — use whichever matches your shell.

    Replaces the placeholder tokens (__ProjectName__, __GoPackage__, __Author__,
    __AuthorEmail__, __GitHubOwner__, __Description__, __Year__) in file contents
    AND in file/folder names, then removes the template-only files (TEMPLATE.md,
    docs/AGENT-INIT-GUIDE.md, and — unless -KeepScript — both initializers,
    init.ps1 and init.sh).

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
    docs/AGENT-INIT-GUIDE.md are removed either way.

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

function Test-Excluded([string]$fullPath) {
    $rel = $fullPath.Substring($repoRoot.Length).TrimStart('\', '/')
    foreach ($seg in ($rel -split '[\\/]')) {
        if ($excludedDirs -contains $seg) { return $true }
    }
    return $false
}

Write-Host "==> Initializing template as '$slug' (package '$goPackage')" -ForegroundColor Cyan

# 1) Replace tokens in file contents. Both initializers are skipped: they carry the
#    literal token strings as search keys, so substituting inside them would corrupt
#    the sibling script.
$siblingSh = Join-Path $PSScriptRoot 'init.sh'
# -Force includes hidden-attributed files (Windows checkouts sometimes hidden-flag
# dot-entries) so this pass sees exactly what init.sh's `find` sees; .git/.jj/vendor
# stay excluded via Test-Excluded.
$files = Get-ChildItem -Path $repoRoot -File -Recurse -Force | Where-Object {
    -not (Test-Excluded $_.FullName) -and $_.FullName -ne $selfPath -and $_.FullName -ne $siblingSh
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

# 2) Rename files and folders whose name contains the project-name token.
#    Deepest paths first so child renames don't invalidate parent paths. The flat
#    Go layout has none, but a cmd/__ProjectName__ adaptation would, so support it.
$named = Get-ChildItem -Path $repoRoot -Recurse -Force | Where-Object {
    -not (Test-Excluded $_.FullName) -and $_.Name -like '*__ProjectName__*'
} | Sort-Object { $_.FullName.Length } -Descending
foreach ($item in $named) {
    $newName = $item.Name.Replace('__ProjectName__', $slug)
    Rename-Item -LiteralPath $item.FullName -NewName $newName
    Write-Host "    Renamed $($item.Name) -> $newName" -ForegroundColor DarkGray
}

# 3) Activate Claude Code shared settings from the shipped .template (renames
#    .claude/settings.json.template -> .claude/settings.json).
$claudeTemplate = Join-Path $repoRoot '.claude/settings.json.template'
if (Test-Path $claudeTemplate) {
    Move-Item -LiteralPath $claudeTemplate -Destination (Join-Path $repoRoot '.claude/settings.json') -Force
    Write-Host "    Activated .claude/settings.json" -ForegroundColor DarkGray
}

# 4) Remove template-only files.
$templateOnly = @('TEMPLATE.md', 'docs/AGENT-INIT-GUIDE.md')
foreach ($rel in $templateOnly) {
    $p = Join-Path $repoRoot $rel
    if (Test-Path $p) { Remove-Item -LiteralPath $p -Force }
}
# Drop docs/ if it's now empty.
$docsDir = Join-Path $repoRoot 'docs'
if ((Test-Path $docsDir) -and -not (Get-ChildItem -LiteralPath $docsDir -Force)) {
    Remove-Item -LiteralPath $docsDir -Force
}

Write-Host ""
Write-Host "Done. Next steps:" -ForegroundColor Green
Write-Host "  1. go build ./... && go test ./..."
Write-Host "  2. gofmt -w . && go vet ./..."
Write-Host "  3. Review LICENSE (author/year) and the module path in go.mod."
Write-Host "  4. Replace greeter.go (and greeter_test.go) with your real API."
Write-Host "  5. Releasing: push a vX.Y.Z tag — no secret needed (proxy.golang.org and"
Write-Host "     pkg.go.dev pick it up). Delete .github/workflows/release.yml if not publishing."
Write-Host "  6. Fill the Architecture section of CLAUDE.md, then commit."

# Remove both initializers unless asked to keep them.
if (-not $KeepScript) {
    if (Test-Path $siblingSh) { Remove-Item -LiteralPath $siblingSh -Force }
    Remove-Item -LiteralPath $selfPath -Force
}
