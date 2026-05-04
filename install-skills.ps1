<#
.SYNOPSIS
    Installs Microsoft skills-for-fabric and copies skills/agents into target folders.

.DESCRIPTION
    This script clones (or updates) the skills-for-fabric repository, runs its install.ps1,
    then ensures skill folders exist directly under ~/.copilot/skills where Copilot usually
    resolves skills. It also copies markdown agent definitions from the repository `agents`
    folder into a scoped target (`~/.copilot/agents` or `<ProjectPath>/.github/agents`).
    Shared files from the repository `common` folder are copied so `../../common/...`
    references continue to resolve from installed skill folders.

    The upstream installer defaults to ~/.copilot/skills/fabric. This script keeps that step,
    then mirrors each installed skill folder to ~/.copilot/skills/<skill-name>.

.PARAMETER RepoUrl
    Git repository URL for skills-for-fabric.

.PARAMETER RepoPath
    Local folder where the repository will be cloned/updated.

.PARAMETER CopilotRoot
    Root Copilot folder. Defaults to ~/.copilot.

.PARAMETER ProjectPath
    Project path passed to upstream install.ps1 for compatibility files.

.PARAMETER SkipCompatibility
    Passed through to upstream install.ps1.

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

$installScript = Join-Path $RepoPath "install.ps1"
if (-not (Test-Path -LiteralPath $installScript)) {
    throw "install.ps1 not found at $installScript"
}

$agentsSource = Join-Path $RepoPath "agents"
if (-not (Test-Path -LiteralPath $agentsSource)) {
    throw "agents folder not found at $agentsSource"
}

$commonSource = Join-Path $RepoPath "common"
if (-not (Test-Path -LiteralPath $commonSource)) {
    throw "common folder not found at $commonSource"
}

$resolvedProjectPath = Resolve-Path -LiteralPath $ProjectPath -ErrorAction SilentlyContinue
if (-not $resolvedProjectPath) {
    Ensure-Directory -Path $ProjectPath
    $resolvedProjectPath = (Resolve-Path -LiteralPath $ProjectPath).Path
} else {
    $resolvedProjectPath = $resolvedProjectPath.Path
}

$stagingRoot = Join-Path $env:TEMP "skills-for-fabric-staging"

if ($InstallScope -eq "Workspace") {
    $skillsRoot = Join-Path $resolvedProjectPath ".github\skills"
    $agentsRoot = Join-Path $resolvedProjectPath ".github\agents"
    $commonRoot = Join-Path $resolvedProjectPath ".github\common"
    $fabricSkillsPath = Join-Path $stagingRoot "fabric"

    Ensure-Directory -Path (Join-Path $resolvedProjectPath ".github")
    Ensure-Directory -Path $skillsRoot
    Ensure-Directory -Path $agentsRoot
    Ensure-Directory -Path $commonRoot

    if (Test-Path -LiteralPath $stagingRoot) {
        Remove-Item -LiteralPath $stagingRoot -Recurse -Force
    }
    Ensure-Directory -Path $stagingRoot

    Write-Info "Workspace install selected. Unwound skills target: $skillsRoot"
    Write-Info "Workspace install selected. Agents target: $agentsRoot"
    Write-Info "Workspace install selected. Common target: $commonRoot"
} else {
    $skillsRoot = Join-Path $CopilotRoot "skills"
    $agentsRoot = Join-Path $CopilotRoot "agents"
    $commonRoot = Join-Path $CopilotRoot "common"
    $fabricSkillsPath = Join-Path $skillsRoot "fabric"

    Ensure-Directory -Path $CopilotRoot
    Ensure-Directory -Path $skillsRoot
    Ensure-Directory -Path $agentsRoot
    Ensure-Directory -Path $commonRoot
}

Write-Status "Running upstream installer to $fabricSkillsPath"

$installParams = @{
    SkillsPath = $fabricSkillsPath
    ProjectPath = $resolvedProjectPath
}
if ($SkipCompatibility) {
    $installParams.SkipCompatibility = $true
}

$pwshCmd = Get-Command pwsh -ErrorAction SilentlyContinue
if ($pwshCmd) {
    Write-Info "Invoking upstream installer with pwsh for compatibility"
    $upstreamArgs = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $installScript,
        "-SkillsPath", $fabricSkillsPath,
        "-ProjectPath", $resolvedProjectPath
    )
    if ($SkipCompatibility) {
        $upstreamArgs += "-SkipCompatibility"
    }

    & $pwshCmd.Source @upstreamArgs
} else {
    Write-Info "pwsh not found; using built-in fallback installer"

    if (Test-Path -LiteralPath $fabricSkillsPath) {
        Write-Info "Removing existing installation..."
        Remove-Item -LiteralPath $fabricSkillsPath -Recurse -Force
    }
    Ensure-Directory -Path $fabricSkillsPath

    $skillsSource = Join-Path $RepoPath "skills"
    if (-not (Test-Path -LiteralPath $skillsSource)) {
        throw "Skills source folder not found at $skillsSource"
    }

    $skillFolders = Get-ChildItem -LiteralPath $skillsSource -Directory
    foreach ($folder in $skillFolders) {
        $dest = Join-Path $fabricSkillsPath $folder.Name
        Copy-Item -LiteralPath $folder.FullName -Destination $dest -Recurse -Force
        Write-Info "Installed: $($folder.Name)"
    }
    Write-Success "Installed $($skillFolders.Count) skills"

    if (-not $SkipCompatibility) {
        Write-Host ""
        Write-Status "Setting up cross-tool compatibility..."

        $compatDir = Join-Path $RepoPath "compatibility"
        if (-not (Test-Path -LiteralPath $compatDir)) {
            throw "Compatibility folder not found at $compatDir"
        }

        $compatFiles = @(
            @{ Name = "CLAUDE.md"; Label = "Claude Code" },
            @{ Name = ".cursorrules"; Label = "Cursor" },
            @{ Name = "AGENTS.md"; Label = "Codex/Jules" },
            @{ Name = ".windsurfrules"; Label = "Windsurf" }
        )

        foreach ($item in $compatFiles) {
            $src = Join-Path $compatDir $item.Name
            $dst = Join-Path $resolvedProjectPath $item.Name

            if (-not (Test-Path -LiteralPath $src)) {
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

    $global:LASTEXITCODE = 0
}

if ($LASTEXITCODE -ne 0) {
    throw "Upstream install.ps1 failed."
}

if (-not (Test-Path -LiteralPath $fabricSkillsPath)) {
    throw "Expected install output at $fabricSkillsPath was not found."
}

Write-Status "Copying installed skills into target folder: $skillsRoot"
$installedSkillDirs = Get-ChildItem -LiteralPath $fabricSkillsPath -Directory

if (-not $installedSkillDirs) {
    throw "No skill directories found under $fabricSkillsPath"
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

if ($InstallScope -eq "Global" -and $RemoveFabricContainer) {
    Write-Status "Removing container folder: $fabricSkillsPath"
    Remove-Item -LiteralPath $fabricSkillsPath -Recurse -Force
}

if ($InstallScope -eq "Workspace" -and (Test-Path -LiteralPath $stagingRoot)) {
    Write-Status "Removing workspace staging folder: $stagingRoot"
    Remove-Item -LiteralPath $stagingRoot -Recurse -Force
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
