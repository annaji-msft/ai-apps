// gateway-sandbox-rbac.bicep
//
// Grants the Connector Gateway's SystemAssigned MI the role needed
// for the ADC proxy to wake the host sandbox in response to a
// trigger event:
//
//   - "Container Apps SandboxGroup Data Owner"
//      (GUID: c24cf47c-5077-412d-a19c-45202126392c)
//
// This is the same role scenario 10's receiver MI got on the sandbox
// group — but here the principal is the gateway MI (because the
// gateway is now the direct caller of the sandbox), not a receiver
// Container App MI.
//
// The role grant alone isn't sufficient — the sandbox's port
// registration (post-deploy) ALSO has to put the gateway MI's
// objectId into its Entra allowlist (`auth.entraId.objectIds`).
// Both must be true for the proxy to wake the sandbox.

@description('Sandbox group resource name (scope of the role assignment).')
param sandboxGroupName string

@description('Principal ID to grant the role to (Connector Gateway MI).')
param principalId string

@description('Container Apps SandboxGroup Data Owner role definition GUID. Documented in azure-rbac as the role required for sandbox wake/create/delete operations.')
param sandboxGroupDataOwnerRoleDefinitionId string = 'c24cf47c-5077-412d-a19c-45202126392c'

resource sandboxGroup 'Microsoft.App/sandboxGroups@2026-02-01-preview' existing = {
  name: sandboxGroupName
}

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: sandboxGroup
  name: guid(sandboxGroup.id, principalId, sandboxGroupDataOwnerRoleDefinitionId)
  properties: {
    principalId: principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', sandboxGroupDataOwnerRoleDefinitionId)
    principalType: 'ServicePrincipal'
  }
}

output roleAssignmentId string = roleAssignment.id
