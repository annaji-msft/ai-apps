// mcpserver-teams.bicep
//
// MCP server configuration on the Connector Gateway that exposes the
// Microsoft Teams "Post message in a chat or channel (V3)" operation
// as an MCP tool. The Connector Gateway publishes the MCP runtime
// endpoint at:
//
//   https://{host}/api/connectorGateways/{connectorGatewayId}/mcpserverconfigs/{name}/mcp
//
// Clients (this scenario: the Copilot CLI running inside an ACA
// sandbox, behind the egress proxy) call the endpoint over MCP
// Streamable HTTP / JSON-RPC 2.0. Authentication is the gateway API
// key (`X-API-Key` header) — the egress proxy stamps it on the way
// out so it never enters the sandbox.

@description('Parent Connector Gateway resource name.')
param gatewayName string

@description('Name for the MCP server config (2-64 chars).')
@minLength(2)
@maxLength(64)
param name string

@description('Description shown to MCP clients via tools/list.')
param mcpDescription string = 'Teams notification tool — post a message to a channel or chat.'

@description('Teams connection name created by the connection-teams module.')
param teamsConnectionName string

resource gateway 'Microsoft.Web/connectorGateways@2026-05-01-preview' existing = {
  name: gatewayName
}

// "kind" defaults to NotSpecified, which builds the MCP surface from
// connectors[].operations[] below. This is the simplest publishing
// shape and works against any managed connector that has the named
// operation in its swagger.
resource mcp 'Microsoft.Web/connectorGateways/mcpserverConfigs@2026-05-01-preview' = {
  parent: gateway
  name: name
  properties: {
    description: mcpDescription
    connectors: [
      {
        name: 'Teams'
        connectionName: teamsConnectionName
        operations: [
          {
            // Swagger operationId for the V3 "Post a message" action.
            // Names with parentheses are normalised to safe MCP tool
            // names by the gateway runtime, so we keep the original
            // operationId here exactly as the connector defines it.
            name: 'Post_message_in_a_chat_or_channel_(V3)'
            displayName: 'Post message in Teams'
            description: 'Post an Adaptive Card or rich text message to a Teams chat or channel.'
          }
        ]
      }
    ]
  }
}

@description('MCP server config name (used by access policies and by clients to construct the runtime URL).')
output name string = mcp.name

@description('Resource ID of the MCP server config.')
output id string = mcp.id
