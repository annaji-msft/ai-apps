// connection-teams.bicep
//
// Microsoft Teams connection on a Connector Gateway. Used to post the
// triage card via the `Teams` managed MCP server config (sibling
// module `mcpserver-teams.bicep`). OAuth consent is completed once
// out-of-band — see the post-deploy script.

@description('Parent Connector Gateway resource name.')
param gatewayName string

@description('Name for the connection (2-64 chars, alphanumeric + hyphen + underscore).')
@minLength(2)
@maxLength(64)
param name string

@description('Friendly display name shown in the Connector Namespace portal.')
param displayName string = 'Microsoft Teams'

resource gateway 'Microsoft.Web/connectorGateways@2026-05-01-preview' existing = {
  name: gatewayName
}

resource connection 'Microsoft.Web/connectorGateways/connections@2026-05-01-preview' = {
  parent: gateway
  name: name
  properties: {
    displayName: displayName
    connectorName: 'Teams'
  }
}

output name string = connection.name
output id string = connection.id
