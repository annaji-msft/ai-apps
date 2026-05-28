// Connector-gateway triggers — minimal azd infra.
//
// All this Bicep template owns is the resource group. Everything else
// (sandbox group + MI, RBAC, connector gateway + MI, office365 connection,
// access policies, OAuth consent, runtime URL) is provisioned by the
// postprovision hook in ../azure.yaml, which delegates to the existing
// setup/python/setup.py.
//
// Why no Bicep for the rest?
//   * The connector-gateway resource types
//     (Microsoft.Web/connectorGateways*@2026-05-01-preview) and the
//     sandbox group type (Microsoft.App/sandboxGroups@2026-02-01-preview)
//     don't have types published yet — Bicep emits BCP081 warnings on
//     every property and gives zero validation.
//   * OAuth consent for the office365 connection is inherently
//     interactive and can't be expressed in ARM.
//   * The existing setup.py is already idempotent and battle-tested;
//     re-using it from the hook means the imperative path and the azd
//     path stay in sync.

targetScope = 'subscription'

@minLength(1)
@description('Name of the azd environment. Tagged on the RG so azd down knows what to delete.')
param environmentName string

@minLength(1)
@description('Primary region. Used as the RG location AND as the sandbox-group region (the sandboxes pillar setup.py uses one region for both). Constrained to the region list returned by Microsoft.App/sandboxGroups so this sample fails fast at deployment time rather than mid-hook. The connector gateway defaults to the same region; override via ACA_CONNECTOR_GATEWAY_REGION.')
@allowed([
  'australiaeast'
  'brazilsouth'
  'canadacentral'
  'canadaeast'
  'centralus'
  'eastasia'
  'eastus2'
  'francecentral'
  'germanywestcentral'
  'japaneast'
  'koreacentral'
  'mexicocentral'
  'northcentralus'
  'northeurope'
  'norwayeast'
  'polandcentral'
  'southafricanorth'
  'southeastasia'
  'southindia'
  'spaincentral'
  'swedencentral'
  'switzerlandnorth'
  'uksouth'
  'westcentralus'
  'westus'
  'westus2'
  'westus3'
])
param location string

@description('Name of the resource group to create. Defaults to ai-apps-samples-rg so it matches the existing scripted baseline; the postprovision hook discovers the same group via samples/.env.')
param resourceGroupName string = 'ai-apps-samples-rg'

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
  tags: {
    'azd-env-name': environmentName
  }
}

output AZURE_RESOURCE_GROUP string = rg.name
output ACA_RESOURCE_GROUP string = rg.name
