// receiver.bicep
//
// ACA environment + Container App that receives the Connector
// Gateway's trigger webhook callbacks. The receiver:
//
//   1. Validates the inbound auth (system key now; Entra-token via
//      built-in App Service auth is a future hardening — see README).
//   2. Parses the email payload from the trigger body.
//   3. Boots an ACA sandbox in the sandbox group using its
//      SystemAssigned MI.
//   4. Runs `copilot` inside the sandbox against the bundled prompt
//      that uses the Teams Managed MCP tool to post a triage card.
//   5. Returns 200 (so the trigger's at-least-once retry doesn't
//      re-fire).
//
// Storage / Log Analytics workspace are created here too so the
// container has somewhere to write logs.

@description('Location for the ACA environment + container app.')
param location string

@description('Tags applied to every resource.')
param tags object = {}

@description('Container image reference for the receiver app. Set by azd to a tag in the registry produced by the receiver service.')
param image string

@description('Resource ID of the sandbox group the receiver boots sandboxes against.')
param sandboxGroupId string

@description('Region of the sandbox group (used by the SDK endpoint resolver).')
param sandboxGroupRegion string

@description('Resource ID of the Connector Gateway (used by post-deploy to look up the API key).')
param connectorGatewayId string

@description('Name of the Teams MCP server config — receiver passes the constructed URL to the sandbox env.')
param teamsMcpServerConfigName string

@description('Name suffix appended to derived resource names. Keep short.')
@minLength(2)
@maxLength(8)
param resourceToken string

var acaEnvName = 'cae-receiver-${resourceToken}'
var receiverAppName = 'ca-receiver-${resourceToken}'
var lawName = 'log-receiver-${resourceToken}'
var uaMiName = 'mi-receiver-${resourceToken}'

resource law 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: lawName
  location: location
  tags: tags
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
    features: { enableLogAccessUsingOnlyResourcePermissions: true }
  }
}

resource ua 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: uaMiName
  location: location
  tags: tags
}

resource env 'Microsoft.App/managedEnvironments@2024-10-02-preview' = {
  name: acaEnvName
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: law.properties.customerId
        sharedKey: law.listKeys().primarySharedKey
      }
    }
    workloadProfiles: [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
    ]
  }
}

resource receiver 'Microsoft.App/containerApps@2024-10-02-preview' = {
  name: receiverAppName
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: { '${ua.id}': {} }
  }
  properties: {
    environmentId: env.id
    workloadProfileName: 'Consumption'
    configuration: {
      ingress: {
        external: true
        targetPort: 8080
        transport: 'http'
        traffic: [
          { weight: 100, latestRevision: true }
        ]
      }
      activeRevisionsMode: 'Single'
    }
    template: {
      containers: [
        {
          name: 'receiver'
          image: image
          resources: {
            cpu: json('0.5')
            memory: '1.0Gi'
          }
          env: [
            {
              name: 'AZURE_CLIENT_ID'
              value: ua.properties.clientId
            }
            {
              name: 'ACA_SANDBOX_GROUP_ID'
              value: sandboxGroupId
            }
            {
              name: 'ACA_SANDBOX_GROUP_REGION'
              value: sandboxGroupRegion
            }
            {
              name: 'CONNECTOR_GATEWAY_ID'
              value: connectorGatewayId
            }
            {
              name: 'TEAMS_MCP_SERVER_CONFIG_NAME'
              value: teamsMcpServerConfigName
            }
          ]
        }
      ]
      scale: {
        minReplicas: 0
        maxReplicas: 5
        rules: [
          {
            name: 'http-burst'
            http: {
              metadata: { concurrentRequests: '10' }
            }
          }
        ]
      }
    }
  }
}

@description('Public FQDN of the receiver Container App. The trigger config callbackUrl points at https://{fqdn}/webhook.')
output fqdn string = receiver.properties.configuration.ingress.fqdn

@description('Public callback URL the Connector Gateway trigger config will POST to.')
output callbackUrl string = 'https://${receiver.properties.configuration.ingress.fqdn}/webhook'

@description('Receiver Container App name (for diagnostics).')
output containerAppName string = receiver.name

@description('User-assigned MI principalId — needed to grant data-plane access on the sandbox group and to the Connector Gateway.')
output principalId string = ua.properties.principalId

@description('User-assigned MI client ID — receiver code uses this for DefaultAzureCredential.')
output clientId string = ua.properties.clientId

@description('User-assigned MI resource ID (for cross-module grants).')
output managedIdentityId string = ua.id
