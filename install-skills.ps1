<#
.SYNOPSIS
    Installs Microsoft skills-for-fabric and copies skills/agents into target folders.

.DESCRIPTION
    This script clones (or updates) the skills-for-fabric repository and installs files
    directly from repository folders. It copies skill folders into a scoped target
    (`~/.copilot/skills` or `<ProjectPath>/.github/skills`), markdown agent definitions
    from `agents`, and shared files from `common` so `../../common/...` references continue
    to resolve from installed skill folders.

    The script supports both repository layouts where `skills`, `agents`, and `common`
    are at the root and plugin-packaged layouts where they are nested under
    `plugins/fabric-skills`.

.PARAMETER RepoUrl
    Git repository URL for skills-for-fabric.

.PARAMETER RepoPath
    Local folder where the repository will be cloned/updated.

.PARAMETER CopilotRoot
    Root Copilot folder. Defaults to ~/.copilot.

.PARAMETER ProjectPath
    Project path used for workspace install and compatibility files.

.PARAMETER SkipCompatibility
    Skips writing compatibility files in the project folder.

.PARAMETER CleanRepo
    If set, removes the local RepoPath before cloning.

.PARAMETER RemoveFabricContainer
    If set, deletes ~/.copilot/skills/fabric after flattening skills to root.

.PARAMETER InstallScope
    Where unwound skills and agents are installed. `Global` installs to ~/.copilot/* (default).
    `Workspace` installs to <ProjectPath>/.github/*.

.EXAMPLE
    .\install-fabric-skills-fixed.ps1

.EXAMPLE
    .\install-fabric-skills-fixed.ps1 -SkipCompatibility -RemoveFabricContainer

.EXAMPLE
    .\install-fabric-skills-fixed.ps1 -InstallScope Workspace -ProjectPath "."
#>

param(
    [string]$RepoUrl = "https://github.com/microsoft/skills-for-fabric.git",
    [string]$RepoPath = "$env:TEMP\\skills-for-fabric",
    [string]$CopilotRoot = "$env:USERPROFILE\\.copilot",
    [string]$ProjectPath = ".",
    [switch]$SkipCompatibility,
    [switch]$CleanRepo,
    [switch]$RemoveFabricContainer,
    [ValidateSet("Global", "Workspace")]
    [string]$InstallScope = "Global"
)

$ErrorActionPreference = "Stop"

function Write-Status([string]$Message) { Write-Host "[*] $Message" -ForegroundColor Cyan }
function Write-Success([string]$Message) { Write-Host "[+] $Message" -ForegroundColor Green }
function Write-Info([string]$Message) { Write-Host "    $Message" -ForegroundColor Gray }

function Ensure-Directory([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Resolve-FirstExistingPath([string[]]$Candidates, [string]$Description) {
    foreach ($candidate in $Candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            return $candidate
        }
    }

    $candidateList = ($Candidates | Where-Object { $_ }) -join ", "
    throw "$Description not found. Checked: $candidateList"
}

function Resolve-FirstExistingPathOrNull([string[]]$Candidates) {
    foreach ($candidate in $Candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            return $candidate
        }
    }

    return $null
}

Write-Host ""
Write-Host "========================================================" -ForegroundColor Magenta
Write-Host " Fabric Skills Installer (Root Skills Folder Fix)" -ForegroundColor Magenta
Write-Host "========================================================" -ForegroundColor Magenta
Write-Host ""

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw "git is required but was not found in PATH."
}

if ($CleanRepo -and (Test-Path -LiteralPath $RepoPath)) {
    Write-Status "Removing existing repo at $RepoPath"
    Remove-Item -LiteralPath $RepoPath -Recurse -Force
}

if (-not (Test-Path -LiteralPath $RepoPath)) {
    Write-Status "Cloning skills repository"
    git clone $RepoUrl $RepoPath
    if ($LASTEXITCODE -ne 0) { throw "git clone failed." }
} else {
    Write-Status "Updating existing repository at $RepoPath"
    git -C $RepoPath pull --ff-only
    if ($LASTEXITCODE -ne 0) { throw "git pull failed. Use -CleanRepo to re-clone." }
}

$skillsSource = Resolve-FirstExistingPath -Candidates @(
    (Join-Path $RepoPath "skills"),
    (Join-Path $RepoPath "plugins\fabric-skills\skills"),
    (Join-Path $RepoPath "plugins\fabric skills\skills")
) -Description "skills folder"

$agentsSource = Resolve-FirstExistingPath -Candidates @(
    (Join-Path $RepoPath "agents"),
    (Join-Path $RepoPath "plugins\fabric-skills\agents"),
    (Join-Path $RepoPath "plugins\fabric skills\agents")
) -Description "agents folder"

$commonSource = Resolve-FirstExistingPath -Candidates @(
    (Join-Path $RepoPath "common"),
    (Join-Path $RepoPath "plugins\fabric-skills\common"),
    (Join-Path $RepoPath "plugins\fabric skills\common")
) -Description "common folder"

$resolvedProjectPath = Resolve-Path -LiteralPath $ProjectPath -ErrorAction SilentlyContinue
if (-not $resolvedProjectPath) {
    Ensure-Directory -Path $ProjectPath
    $resolvedProjectPath = (Resolve-Path -LiteralPath $ProjectPath).Path
} else {
    $resolvedProjectPath = $resolvedProjectPath.Path
}

if ($InstallScope -eq "Workspace") {
    $skillsRoot = Join-Path $resolvedProjectPath ".github\skills"
    $agentsRoot = Join-Path $resolvedProjectPath ".github\agents"
    $commonRoot = Join-Path $resolvedProjectPath ".github\common"

    Ensure-Directory -Path (Join-Path $resolvedProjectPath ".github")
    Ensure-Directory -Path $skillsRoot
    Ensure-Directory -Path $agentsRoot
    Ensure-Directory -Path $commonRoot

    Write-Info "Workspace install selected. Unwound skills target: $skillsRoot"
    Write-Info "Workspace install selected. Agents target: $agentsRoot"
    Write-Info "Workspace install selected. Common target: $commonRoot"
} else {
    $skillsRoot = Join-Path $CopilotRoot "skills"
    $agentsRoot = Join-Path $CopilotRoot "agents"
    $commonRoot = Join-Path $CopilotRoot "common"

    Ensure-Directory -Path $CopilotRoot
    Ensure-Directory -Path $skillsRoot
    Ensure-Directory -Path $agentsRoot
    Ensure-Directory -Path $commonRoot
}

Write-Info "Using skills source: $skillsSource"
Write-Info "Using agents source: $agentsSource"
Write-Info "Using common source: $commonSource"

Write-Status "Copying installed skills into target folder: $skillsRoot"
$installedSkillDirs = Get-ChildItem -LiteralPath $skillsSource -Directory

if (-not $installedSkillDirs) {
    throw "No skill directories found under $skillsSource"
}

foreach ($skillDir in $installedSkillDirs) {
    $destination = Join-Path $skillsRoot $skillDir.Name

    if (Test-Path -LiteralPath $destination) {
        Remove-Item -LiteralPath $destination -Recurse -Force
        Write-Info "Replaced existing: $($skillDir.Name)"
    }

    Copy-Item -LiteralPath $skillDir.FullName -Destination $destination -Recurse -Force
    Write-Info "Installed to root: $($skillDir.Name)"
}

if (-not $SkipCompatibility) {
    Write-Host ""
    Write-Status "Setting up cross-tool compatibility..."

    $compatFiles = @(
        @{ Name = "CLAUDE.md"; Label = "Claude Code" },
        @{ Name = ".cursorrules"; Label = "Cursor" },
        @{ Name = "AGENTS.md"; Label = "Codex/Jules" },
        @{ Name = ".windsurfrules"; Label = "Windsurf" }
    )

    foreach ($item in $compatFiles) {
        $src = Resolve-FirstExistingPathOrNull -Candidates @(
            (Join-Path $RepoPath "compatibility\$($item.Name)"),
            (Join-Path $RepoPath "plugins\fabric-skills\compatibility\$($item.Name)"),
            (Join-Path $RepoPath "plugins\fabric skills\compatibility\$($item.Name)"),
            (Join-Path $RepoPath $item.Name)
        )

        $dst = Join-Path $resolvedProjectPath $item.Name

        if (-not $src) {
            Write-Info "Skipped: $($item.Name) (missing in repo)"
            continue
        }

        if (-not (Test-Path -LiteralPath $dst)) {
            Copy-Item -LiteralPath $src -Destination $dst -Force
            Write-Info "Created: $($item.Name) ($($item.Label))"
        } else {
            Write-Info "Skipped: $($item.Name) (already exists)"
        }
    }

    Write-Success "Compatibility files configured"
}

Write-Status "Copying common files into target folder: $commonRoot"
if (Test-Path -LiteralPath $commonRoot) {
    Remove-Item -LiteralPath $commonRoot -Recurse -Force
}
Copy-Item -LiteralPath $commonSource -Destination $commonRoot -Recurse -Force
Write-Success "Installed common files"

Write-Status "Copying agent markdown files into target folder: $agentsRoot"
$agentFiles = Get-ChildItem -LiteralPath $agentsSource -File -Filter "*.md"

if (-not $agentFiles) {
    Write-Info "No .md agent files found under $agentsSource"
} else {
    foreach ($agentFile in $agentFiles) {
        $agentDestination = Join-Path $agentsRoot $agentFile.Name

        if (Test-Path -LiteralPath $agentDestination) {
            Remove-Item -LiteralPath $agentDestination -Force
            Write-Info "Replaced existing agent: $($agentFile.Name)"
        }

        Copy-Item -LiteralPath $agentFile.FullName -Destination $agentDestination -Force
        Write-Info "Installed agent: $($agentFile.Name)"
    }

    Write-Success "Installed $($agentFiles.Count) agents"
}

if ($RemoveFabricContainer) {
    Write-Info "RemoveFabricContainer is not applicable with direct folder install and was ignored."
}

Write-Host ""
Write-Success "Done. Skills are available directly under: $skillsRoot"
Write-Success "Done. Agents are available directly under: $agentsRoot"
Write-Success "Done. Common files are available directly under: $commonRoot"
Write-Host ""
Write-Host "Validation commands:" -ForegroundColor White
Write-Host ('  Get-ChildItem "{0}" -Directory | Select-Object -ExpandProperty Name' -f $skillsRoot) -ForegroundColor Gray
Write-Host ('  Get-ChildItem "{0}" -File | Select-Object -ExpandProperty Name' -f $commonRoot) -ForegroundColor Gray
Write-Host ('  Get-ChildItem "{0}" -File -Filter "*.md" | Select-Object -ExpandProperty Name' -f $agentsRoot) -ForegroundColor Gray
Write-Host ""
