# Windows启动脚本：proxy_bridge + claude-mem worker
# 用法: .\start-relay-chain.ps1
# 或带参数: .\start-relay-chain.ps1 -SkipProxy -Verbose

param(
    [switch]$SkipProxy,
    [switch]$Verbose
)

$ErrorActionPreference = "Stop"
$WarningPreference = "Continue"

# 配置
$PROXY_HOST = "127.0.0.1"
$PROXY_PORT = 4000
$WORKER_PORT = 37778
$UPSTREAM_API_KEY = "CC6368A4-BB47-4AB4-B18B-41EF5963B985"
$WSL_DISTRO = "Ubuntu-24.04"
$PROXY_SCRIPT_PATH = "/home/laserqc/litellm/proxy_bridge.py"
$HEALTH_CHECK_TIMEOUT = 30

function Write-Status {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "HH:mm:ss"
    $color = @{
        "INFO"    = "Cyan"
        "SUCCESS" = "Green"
        "WARN"    = "Yellow"
        "ERROR"   = "Red"
    }[$Level]
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $color
}

function Test-PortOpen {
    param([string]$HostName, [int]$Port, [int]$TimeoutSeconds = 5)
    $tcpClient = New-Object System.Net.Sockets.TcpClient
    $asyncResult = $tcpClient.BeginConnect($HostName, $Port, $null, $null)
    $wait = $asyncResult.AsyncWaitHandle.WaitOne([timespan]::FromSeconds($TimeoutSeconds))
    if ($wait) {
        try {
            $tcpClient.EndConnect($asyncResult)
            return $true
        } catch {
            return $false
        }
    } else {
        return $false
    }
}

function Start-ProxyBridge {
    Write-Status "Starting proxy_bridge.py in WSL..." "INFO"

    # Kill old process
    $oldPid = wsl -d $WSL_DISTRO -- bash -c "pgrep -f proxy_bridge 2>/dev/null || echo ''" 2>$null
    if ($oldPid) {
        Write-Status "Killing old proxy_bridge (PID: $oldPid)" "WARN"
        wsl -d $WSL_DISTRO -- bash -c "kill $oldPid 2>/dev/null; exit 0" 2>$null
        Start-Sleep -Seconds 1
    }

    # Start new process
    $cmd = @"
cd /home/laserqc/litellm && `
UPSTREAM_API_KEY='$UPSTREAM_API_KEY' `
nohup python3 proxy_bridge.py > /tmp/proxy_bridge.log 2>&1 & `
sleep 1 && `
pgrep -f proxy_bridge || echo 'FAILED'
"@

    $result = wsl -d $WSL_DISTRO -- bash -c $cmd 2>$null
    if ($result -match "FAILED") {
        Write-Status "Failed to start proxy_bridge" "ERROR"
        return $false
    }

    Write-Status "proxy_bridge started (PID: $result)" "SUCCESS"
    return $true
}

function Wait-PortReady {
    param([string]$HostName, [int]$Port, [string]$Name)

    Write-Status "Waiting for $Name to be ready on ${HostName}:${Port}..." "INFO"
    $elapsed = 0

    while ($elapsed -lt $HEALTH_CHECK_TIMEOUT) {
        if (Test-PortOpen -HostName $HostName -Port $Port -TimeoutSeconds 2) {
            Write-Status "$Name is ready" "SUCCESS"
            return $true
        }
        Start-Sleep -Seconds 1
        $elapsed += 1
    }

    Write-Status "$Name did not become ready within ${HEALTH_CHECK_TIMEOUT}s" "ERROR"
    return $false
}

function Test-ProxyHealth {
    try {
        $response = Invoke-WebRequest -Uri "http://${PROXY_HOST}:${PROXY_PORT}/health" `
            -TimeoutSec 5 -ErrorAction Stop
        $health = $response.Content | ConvertFrom-Json

        if ($health.status -eq "ok") {
            Write-Status "Proxy health check passed" "SUCCESS"
            Write-Status "  Upstream: $($health.upstream)" "INFO"
            Write-Status "  Config: concurrent=$($health.config.max_concurrent) retries=$($health.config.max_retries) timeout=$($health.config.timeout_seconds)s rpm=$($health.config.rpm_limit)" "INFO"
            return $true
        }
    } catch {
        Write-Status "Proxy health check failed: $_" "ERROR"
    }
    return $false
}

function Start-ClaudeMemWorker {
    Write-Status "Starting claude-mem worker..." "INFO"

    # Kill old worker process
    $oldWorker = Get-Process -Name "node" -ErrorAction SilentlyContinue | `
        Where-Object { $_.CommandLine -match "claude-mem|worker" }

    if ($oldWorker) {
        Write-Status "Killing old worker process" "WARN"
        $oldWorker | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }

    # Delete PID file if exists
    $pidFile = "$env:APPDATA\.claude-mem\worker.pid"
    if (Test-Path $pidFile) {
        Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
    }

    # Start worker via npm
    Push-Location "D:\GitHub\claude-mem"
    try {
        Write-Status "Running: npm run worker:start" "INFO"
        & npm run worker:start 2>&1 | ForEach-Object {
            if ($Verbose) { Write-Host $_ }
        }

        if ($LASTEXITCODE -ne 0) {
            Write-Status "Worker start command failed with exit code $LASTEXITCODE" "ERROR"
            return $false
        }
    } finally {
        Pop-Location
    }

    Write-Status "Worker started" "SUCCESS"
    return $true
}

function Test-WorkerHealth {
    try {
        $response = Invoke-WebRequest -Uri "http://127.0.0.1:${WORKER_PORT}/health" `
            -TimeoutSec 5 -ErrorAction Stop
        $health = $response.Content | ConvertFrom-Json

        Write-Status "Worker health check passed" "SUCCESS"
        Write-Status "  Status: $($health.status)" "INFO"
        return $true
    } catch {
        Write-Status "Worker health check failed: $_" "WARN"
        return $false
    }
}

# Main flow
Write-Status "=== Claude-Mem Relay Chain Startup ===" "INFO"

if (-not $SkipProxy) {
    if (-not (Start-ProxyBridge)) {
        Write-Status "Failed to start proxy_bridge" "ERROR"
        exit 1
    }

    if (-not (Wait-PortReady -HostName $PROXY_HOST -Port $PROXY_PORT -Name "proxy_bridge")) {
        Write-Status "Proxy bridge failed to become ready" "ERROR"
        exit 1
    }

    if (-not (Test-ProxyHealth)) {
        Write-Status "Proxy health check failed" "ERROR"
        exit 1
    }
} else {
    Write-Status "Skipping proxy_bridge startup (--SkipProxy)" "WARN"
}

if (-not (Start-ClaudeMemWorker)) {
    Write-Status "Failed to start claude-mem worker" "ERROR"
    exit 1
}

if (-not (Wait-PortReady -HostName "127.0.0.1" -Port $WORKER_PORT -Name "claude-mem worker")) {
    Write-Status "Worker failed to become ready" "ERROR"
    exit 1
}

Start-Sleep -Seconds 2
if (-not (Test-WorkerHealth)) {
    Write-Status "Worker health check failed (non-fatal, may still be initializing)" "WARN"
}

Write-Status "=== Startup Complete ===" "SUCCESS"
Write-Status "Proxy bridge: http://${PROXY_HOST}:${PROXY_PORT}" "INFO"
Write-Status "Worker: http://127.0.0.1:${WORKER_PORT}" "INFO"
Write-Status "Web UI: http://localhost:37777" "INFO"
