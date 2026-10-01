$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$envPath = Join-Path $repoRoot ".env"

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

Write-Host "[2/3] Starting litellm proxy on port 4000..." -ForegroundColor Cyan
# Launch the proxy in its own window so it keeps running while codex is used
$configPath = Join-Path $repoRoot "config\nvidiaAPI\litellm_config.yaml"
$proxy = Start-Process pipenv -ArgumentList "run", "litellm", "--config", $configPath, "--port", "4000" -PassThru -WindowStyle Normal

# Give the proxy a few seconds to bind before codex tries to connect
Start-Sleep -Seconds 5

Write-Host "[3/3] Launching codex! (Type 'exit' or close the window to stop)" -ForegroundColor Green
Write-Host "-----------------------------------------------------------"
codex

Write-Host "-----------------------------------------------------------"
Write-Host "[Clean-up] Stopping litellm proxy..." -ForegroundColor Yellow
if ($proxy -and -not $proxy.HasExited) {
    Stop-Process -Id $proxy.Id -Force
}
