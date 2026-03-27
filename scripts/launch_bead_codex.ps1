Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Fail {
    param([string]$Message)

    [Console]::Error.WriteLine("ERROR: $Message")
    exit 1
}

function Require-Command {
    param([string]$Name)

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        Fail "Missing required command: $Name"
    }
}

Require-Command git
$repoRoot = (& git rev-parse --show-toplevel 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($repoRoot)) {
    Fail 'Not inside a git repository.'
}

Set-Location $repoRoot

foreach ($commandName in 'bd', 'codex', 'poetry') {
    Require-Command $commandName
}

$baseBranch = (& git symbolic-ref --quiet --short HEAD 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($baseBranch)) {
    Fail 'Detached HEAD detected. Check out a branch before launching Codex.'
}

$poetryEnv = (& poetry env info --path 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($poetryEnv) -or -not (Test-Path $poetryEnv)) {
    Fail 'Unable to resolve the Poetry environment for this repo.'
}

$venvBin = Join-Path $poetryEnv 'Scripts'
if (-not (Test-Path $venvBin)) {
    $venvBin = Join-Path $poetryEnv 'bin'
}
if (-not (Test-Path $venvBin)) {
    Fail "Poetry environment executable directory does not exist under $poetryEnv"
}

$claimedId = $null
$lastError = $null

for ($attempt = 1; $attempt -le 3 -and -not $claimedId; $attempt++) {
    $readyJson = (& bd ready --json 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) {
        Fail "bd ready --json failed: $readyJson"
    }

    $issues = @()
    if (-not [string]::IsNullOrWhiteSpace($readyJson)) {
        $parsed = $readyJson | ConvertFrom-Json
        if ($null -ne $parsed) {
            $issues = @($parsed)
        }
    }

    $candidateIds = @($issues | Where-Object { $_ -and $_.id } | ForEach-Object { [string]$_.id })
    if ($candidateIds.Count -eq 0) {
        if ($lastError) {
            Fail "No bead could be claimed after $($attempt - 1) retries. Last claim error: $lastError"
        }
        Fail 'No ready beads available to claim.'
    }

    $candidateId = $candidateIds[0]
    $claimOutput = (& bd update $candidateId --claim --json 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -eq 0) {
        $claimedId = $candidateId
        break
    }

    $lastError = $claimOutput
    Write-Warning "Claim attempt $attempt/3 failed for bead ${candidateId}: $claimOutput"
}

if (-not $claimedId) {
    Fail "Unable to claim a bead after 3 attempts. Last claim error: $lastError"
}

$worktreesDir = Join-Path $repoRoot '.worktrees'
if (-not (Test-Path $worktreesDir)) {
    New-Item -ItemType Directory -Path $worktreesDir | Out-Null
}

$worktreeRel = ".worktrees/$claimedId"
$worktreePath = Join-Path $worktreesDir $claimedId
$taskBranch = "agent/$claimedId"

if (Test-Path $worktreePath) {
    Fail "Worktree path already exists: $worktreePath"
}

# Fail instead of guessing whether reusing an existing agent branch is safe.
& git show-ref --verify --quiet "refs/heads/$taskBranch"
if ($LASTEXITCODE -eq 0) {
    Fail "Branch already exists: $taskBranch"
}

& git worktree add $worktreeRel -b $taskBranch $baseBranch
if ($LASTEXITCODE -ne 0) {
    Fail "Failed to create worktree at $worktreePath"
}

Write-Host "Claimed bead: $claimedId"
Write-Host "Base branch: $baseBranch"
Write-Host "Worktree: $worktreePath"

$env:VIRTUAL_ENV = $poetryEnv
$env:POETRY_ACTIVE = '1'
$env:PATH = "$venvBin;$env:PATH"

$prompt = "bead $claimedId has been claimed for you to work on in the current git branch and worktree, please work on it"
codex --cd $worktreeRel $prompt
