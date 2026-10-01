$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$envPath = Join-Path $repoRoot ".env"
$port = 4000

Write-Host "[1/3] Loading NVIDIA_API_KEY from .env..." -ForegroundColor Cyan
if (-not $env:NVIDIA_API_KEY) {
    if (-not (Test-Path $envPath)) {
        throw ".env file not found at $envPath"
    }
    $line = Get-Content $envPath | Where-Object { $_ -match '^\s*NVIDIA_API_KEY\s*=' } | Select-Object -First 1
    if (-not $line) {
        throw "NVIDIA_API_KEY not found in $envPath"
    }
    $env:NVIDIA_API_KEY = ($line -split '=', 2)[1].Trim().Trim('"')
}

Write-Host "[2/3] Starting litellm proxy on port $port..." -ForegroundColor Cyan
# Launch the proxy in its own window so its logs stay visible while Claude Code runs
$configPath = Join-Path $repoRoot "config\nvidiaAPI\litellm_config.yaml"
$proxy = Start-Process pipenv -ArgumentList "run", "litellm", "--config", $configPath, "--port", $port `
    -WorkingDirectory $repoRoot -PassThru -WindowStyle Normal

# litellm can take a while to start; wait until it answers
$healthUrl = "http://localhost:$port/health/liveliness"
$ready = $false
$deadline = (Get-Date).AddSeconds(120)
while ((Get-Date) -lt $deadline) {
    try {
        # The first request is slow (~2-3s, cold proxy), so give each attempt a generous timeout
        Invoke-WebRequest -Uri $healthUrl -UseBasicParsing -TimeoutSec 15 | Out-Null
        $ready = $true
        break
    } catch { Start-Sleep -Seconds 1 }
}
if (-not $ready) { Write-Warning "Proxy did not answer on $healthUrl within 120s; continuing anyway." }

# Point Claude Code at the proxy. These exist only in this process.
$env:ANTHROPIC_BASE_URL = "http://localhost:$port"
$env:ANTHROPIC_AUTH_TOKEN = "anything"
Remove-Item Env:ANTHROPIC_API_KEY -ErrorAction SilentlyContinue
$env:ANTHROPIC_MODEL = "nvidia-model"
$env:ANTHROPIC_SMALL_FAST_MODEL = "nvidia-model"
$env:ANTHROPIC_DEFAULT_OPUS_MODEL = "nvidia-model"
$env:ANTHROPIC_DEFAULT_SONNET_MODEL = "nvidia-model"
$env:ANTHROPIC_DEFAULT_HAIKU_MODEL = "nvidia-model"
# Context window of the model in litellm_config.yaml (gpt-oss-20b: 131072); keeps auto-compact accurate
$env:CLAUDE_CODE_MAX_CONTEXT_TOKENS = "131072"
# Don't send telemetry / update checks to Anthropic while using a third-party backend
$env:CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1"

Write-Host "[3/3] Launching Claude Code! (exit Claude Code to stop the proxy)" -ForegroundColor Green
Write-Host "-----------------------------------------------------------"
try {
    claude @args
} finally {
    Write-Host "-----------------------------------------------------------"
    Write-Host "[Clean-up] Stopping litellm proxy..." -ForegroundColor Yellow
    if ($proxy -and -not $proxy.HasExited) {
        # /T also stops the child processes pipenv started
        & "$env:SystemRoot\System32\taskkill.exe" /PID $proxy.Id /T /F | Out-Null
    }
}
