# Web app deployment - run a Node.js HTTP server in a sandbox, expose it (aca CLI).

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

$SandboxId = $null
$AppFile   = Join-Path $env:TEMP 'aca-sample-index.js'

$appCode = @'
const http = require('http');
const os = require('os');
http.createServer((req, res) => {
  res.writeHead(200, {'Content-Type': 'application/json'});
  res.end(JSON.stringify({
    message: 'Hello from sandbox!',
    hostname: os.hostname(),
    uptime: process.uptime(),
    path: req.url,
  }, null, 2));
}).listen(8080, '0.0.0.0', () => console.log('Server on :8080'));
'@

try {
    Set-Content -Path $AppFile -Value $appCode -NoNewline

    Write-Host "==> Booting sandbox from 'node-22' disk image..."
    $createOutput = aca sandbox create --disk node-22 | Out-String
    $match = [regex]::Match($createOutput, '(?m)^Created sandbox:\s*(\S+)')
    if (-not $match.Success) { throw 'Could not parse sandbox id' }
    $SandboxId = $match.Groups[1].Value
    Write-Host "    sandbox: $SandboxId"
    Start-Sleep -Seconds 10

    Write-Host '==> Uploading /app/index.js...'
    aca sandbox fs mkdir --id $SandboxId --path /app 2>$null | Out-Null
    aca sandbox fs write --id $SandboxId --path /app/index.js --file $AppFile

    Write-Host '==> Starting server (nohup node /app/index.js)...'
    aca sandbox exec --id $SandboxId -c "cd /app && nohup node index.js > /tmp/node.log 2>&1 &"
    Start-Sleep -Seconds 3

    Write-Host '    in-sandbox curl:'
    aca sandbox exec --id $SandboxId -c "curl -s http://localhost:8080 || cat /tmp/node.log"

    Write-Host '==> Publishing port 8080...'
    $portJson = aca sandbox port add --id $SandboxId --port 8080 --anonymous -o json | Out-String
    $Url = ($portJson | ConvertFrom-Json).url
    Write-Host "    public URL: $Url"
    if (-not $Url) { throw 'no URL in add port response' }

    Write-Host '==> Hitting public URL from this machine...'
    Start-Sleep -Seconds 8
    $response = Invoke-WebRequest -Uri $Url -TimeoutSec 15 -UseBasicParsing
    $body = if ($response.Content -is [byte[]]) {
        [Text.Encoding]::UTF8.GetString($response.Content)
    } else {
        $response.Content
    }
    Write-Host $body

    Write-Host '==> Done.'
}
finally {
    if ($SandboxId) {
        Write-Host "==> Deleting sandbox $SandboxId..."
        aca sandbox delete --id $SandboxId --yes 2>$null | Out-Null
    }
    Remove-Item -Force -ErrorAction SilentlyContinue $AppFile
}
