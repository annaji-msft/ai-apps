# Hello World sample for the Azure Container Apps Sandboxes CLI.
#
# Creates an Ubuntu sandbox, runs a command, prints the output, and deletes
# the sandbox. Requires an active sandbox-group config (see README.md).

$ErrorActionPreference = 'Stop'

Write-Host 'Creating sandbox...'
$sandboxId = (aca sandbox create --disk ubuntu -o tsv --query id).Trim()
Write-Host "Created sandbox: $sandboxId"

try {
    aca sandbox exec --id $sandboxId -c "echo hello world && uname -a"
}
finally {
    aca sandbox delete --id $sandboxId --yes | Out-Null
    Write-Host "Deleted sandbox $sandboxId."
}
