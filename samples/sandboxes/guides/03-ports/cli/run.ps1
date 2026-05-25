# Ports - expose port 8080 and hit it from outside the sandbox (aca CLI).

$ErrorActionPreference = 'Stop'

$dir = $PSScriptRoot
while ($dir -and -not (Test-Path (Join-Path $dir '.env'))) {
    $parent = Split-Path $dir -Parent
    if ($parent -eq $dir) { break }
    $dir = $parent
}
$envFile = Join-Path $dir '.env'
if (-not (Test-Path $envFile)) {
    Write-Error "Could not find samples/.env - run setup/setup.py first?"
    exit 1
}
Get-Content $envFile | ForEach-Object {
    if ($_ -and -not $_.StartsWith('#') -and $_.Contains('=')) {
        $k, $v = $_.Split('=', 2)
        [Environment]::SetEnvironmentVariable($k.Trim(), $v.Trim(), 'Process')
    }
}

Write-Host '==> Creating sandbox...'
$createOutput = aca sandbox create --disk ubuntu | Out-String
$match = [regex]::Match($createOutput, '(?m)^Created sandbox:\s*(\S+)')
if (-not $match.Success) { throw 'Could not parse sandbox id' }
$SandboxId = $match.Groups[1].Value
Write-Host "    sandbox: $SandboxId"

try {
    Write-Host '==> Starting tiny HTTP server inside the sandbox on :8080...'
    $serverCmd = "nohup python3 -c `"import http.server,socketserver; h=http.server.BaseHTTPRequestHandler; h.do_GET=lambda s:(s.send_response(200),s.end_headers(),s.wfile.write(b'hello from sandbox\n')); socketserver.TCPServer(('0.0.0.0',8080), h).serve_forever()`" > /tmp/srv.log 2>&1 &"
    aca sandbox exec --id $SandboxId -c $serverCmd
    Start-Sleep -Seconds 2

    Write-Host '==> aca sandbox port add 8080 --anonymous'
    $portJson = aca sandbox port add --id $SandboxId --port 8080 --anonymous -o json | Out-String
    $port = $portJson | ConvertFrom-Json
    $Url = $port.url
    Write-Host "    public URL: $Url"
    if (-not $Url) { throw 'no URL in add port response' }

    Write-Host '==> Curling public URL from this machine...'
    Start-Sleep -Seconds 6
    $response = Invoke-WebRequest -Uri $Url -TimeoutSec 15 -UseBasicParsing
    $body = if ($response.Content -is [byte[]]) {
        [Text.Encoding]::UTF8.GetString($response.Content)
    } else {
        $response.Content
    }
    Write-Host "    response: $($body.Trim())"

    Write-Host '==> aca sandbox port remove --port 8080'
    aca sandbox port remove --id $SandboxId --port 8080

    Write-Host '==> Done.'
}
finally {
    Write-Host "==> Deleting sandbox $SandboxId..."
    aca sandbox delete --id $SandboxId --yes | Out-Null
}
