$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$envPath = Join-Path $repoRoot ".env"
$configPath = Join-Path $repoRoot "config\nvidiaAPI\litellm_config.yaml"
$port = 4000
$proxy = $null

function Import-NvidiaApiKey {
    Write-Host "[1/3] Loading NVIDIA_API_KEY from .env..." -ForegroundColor Cyan
    if ($env:NVIDIA_API_KEY) { return }
    if (-not (Test-Path $envPath)) { throw ".env file not found at $envPath" }

    $line = Get-Content $envPath | Where-Object { $_ -match '^\s*NVIDIA_API_KEY\s*=' } | Select-Object -First 1
    if (-not $line) { throw "NVIDIA_API_KEY not found in $envPath" }

    $value = ($line -split '=', 2)[1].Trim()
    if (($value.StartsWith('"') -and $value.EndsWith('"')) -or
        ($value.StartsWith("'") -and $value.EndsWith("'"))) {
        $value = $value.Substring(1, $value.Length - 2)
    }
    if (-not $value) { throw "NVIDIA_API_KEY is empty in $envPath" }
    $env:NVIDIA_API_KEY = $value
}

function Start-LiteLLMProxy {
    Write-Host "[2/3] Starting litellm proxy on port $port..." -ForegroundColor Cyan
    Start-Process pipenv -ArgumentList "run", "litellm", "--config", $configPath, "--port", $port `
        -WorkingDirectory $repoRoot -PassThru -WindowStyle Normal
}

function Wait-ForProxy {
    $healthUrl = "http://localhost:$port/health/liveliness"
    $deadline = (Get-Date).AddSeconds(120)
    while ((Get-Date) -lt $deadline) {
        try {
            Invoke-WebRequest -Uri $healthUrl -UseBasicParsing -TimeoutSec 15 | Out-Null
            return
        } catch { Start-Sleep -Seconds 1 }
    }
    Write-Warning "Proxy did not answer on $healthUrl within 120s; continuing anyway."
}

function Stop-LiteLLMProxy {
    if ($proxy -and -not $proxy.HasExited) {
        & "$env:SystemRoot\System32\taskkill.exe" /PID $proxy.Id /T /F | Out-Null
    }
}

Import-NvidiaApiKey
$proxy = Start-LiteLLMProxy
try {
    Wait-ForProxy
    Write-Host "[3/3] Launching Codex! (exit Codex to stop the proxy)" -ForegroundColor Green
    Write-Host "-----------------------------------------------------------"
    codex @args
} finally {
    Write-Host "-----------------------------------------------------------"
    Write-Host "[Clean-up] Stopping litellm proxy..." -ForegroundColor Yellow
    Stop-LiteLLMProxy
}
