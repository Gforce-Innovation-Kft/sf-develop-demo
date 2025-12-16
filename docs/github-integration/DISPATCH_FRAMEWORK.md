## 🏗️ GitHub Dispatch Event Framework

Structured framework for dispatching multiple event types to GitHub Actions with consistent patterns and easy extensibility.

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Salesforce                               │
│                                                              │
│  ┌───────────────────────────────────────────────────┐     │
│  │        GitHubDispatchEvent (Abstract)             │     │
│  │  • getEventType()                                 │     │
│  │  • buildPayload()                                 │     │
│  │  • validate()                                     │     │
│  └────────────┬──────────────────────────────────────┘     │
│               │ extends                                     │
│               ├─────────────────┬──────────────────┐       │
│               ▼                 ▼                  ▼        │
│  ┌──────────────────┐  ┌─────────────┐  ┌─────────────┐  │
│  │ DeploymentEvent  │  │TestResult   │  │ DataSync    │  │
│  │                  │  │Event        │  │ Event       │  │
│  └──────────────────┘  └─────────────┘  └─────────────┘  │
│               │                 │                  │        │
│               └─────────────────┴──────────────────┘       │
│                              │                              │
│                              ▼                              │
│            ┌──────────────────────────────────┐            │
│            │   GitHubDispatchService          │            │
│            │  • dispatch(event)               │            │
│            │  • dispatchBatch(events)         │            │
│            └──────────────┬───────────────────┘            │
└───────────────────────────┼────────────────────────────────┘
                            │ HTTPS
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                     GitHub API                               │
│  POST /repos/{owner}/{repo}/dispatches                       │
│  {                                                           │
│    "event_type": "deployment_requested",                    │
│    "client_payload": { ... }                                │
│  }                                                           │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                 GitHub Actions Workflows                     │
│  • dispatch-deployment.yml                                   │
│  • dispatch-test-result.yml                                  │
│  • dispatch-data-sync.yml                                    │
└─────────────────────────────────────────────────────────────┘
```

### Components

#### 1. GitHubDispatchEvent (Abstract Base Class)

Provides structure for all events:

```apex
public abstract class GitHubDispatchEvent {
  // Required: Event type identifier
  public abstract String getEventType();

  // Required: Build the payload
  public abstract Map<String, Object> buildPayload();

  // Optional: Custom validation
  public virtual Boolean validate() {
  }

  // Optional: Get metadata
  public virtual Map<String, Object> getMetadata() {
  }
}
```

#### 2. GitHubDispatchService (Dispatcher)

Handles sending events to GitHub:

```apex
public with sharing class GitHubDispatchService {
  // Send single event
  public Boolean dispatch(GitHubDispatchEvent event) {
  }

  // Send multiple events
  public Map<String, Boolean> dispatchBatch(List<GitHubDispatchEvent> events) {
  }
}
```

#### 3. Concrete Event Classes

Pre-built event types ready to use:

- **DeploymentEvent** - Trigger deployments
- **TestResultEvent** - Send test results
- **DataSyncEvent** - Sync data to external systems

### Quick Start

#### Example 1: Trigger Deployment

```apex
// Create deployment event
DeploymentEvent event = new DeploymentEvent('staging', 'Opportunity', '0065000000XXXXX')
    .setRunTests(true)
    .setMessage('Opportunity closed - deploying configuration');

// Dispatch to GitHub
new GitHubDispatchService().dispatch(event);
```

**GitHub receives:**

```json
{
  "event_type": "deployment_requested",
  "client_payload": {
    "environment": "staging",
    "recordType": "Opportunity",
    "recordId": "0065000000XXXXX",
    "runTests": true,
    "message": "Opportunity closed - deploying configuration",
    "triggeredBy": "John Doe",
    "timestamp": "2025-12-16T10:30:00Z"
  }
}
```

#### Example 2: Send Test Results

```apex
// Create test result event
TestResultEvent event = new TestResultEvent(false, 'AccountTriggerTest', 72.5)
    .setMessage('Timeout in trigger execution')
    .setErrorDetails('System.LimitException: Apex CPU time limit exceeded');

// Dispatch
new GitHubDispatchService().dispatch(event);
```

#### Example 3: Sync Data

```apex
// Create data sync event
DataSyncEvent event = new DataSyncEvent('Account', '0015000000XXXXX')
    .setOperation('update')
    .addField('Name', 'Acme Corporation')
    .addField('Industry', 'Technology')
    .addField('AnnualRevenue', 5000000);

// Dispatch
new GitHubDispatchService().dispatch(event);
```

#### Example 4: Batch Dispatch

```apex
// Create multiple events
List<GitHubDispatchEvent> events = new List<GitHubDispatchEvent>{
    new DeploymentEvent('sandbox', 'Account', '001...'),
    new TestResultEvent(true, 'AccountTest', 85.0),
    new DataSyncEvent('Contact', '003...').addField('Email', 'test@example.com')
};

// Dispatch all at once
Map<String, Boolean> results = new GitHubDispatchService().dispatchBatch(events);

// Check results
for (String eventType : results.keySet()) {
    System.debug(eventType + ': ' + (results.get(eventType) ? '✅' : '❌'));
}
```

### Creating Custom Events

#### Step 1: Create Event Class

```apex
public class CustomEvent extends GitHubDispatchEvent {
  private String customField;

  public CustomEvent(String customField) {
    this.customField = customField;
  }

  public override String getEventType() {
    return 'custom_event_type'; // Must match workflow
  }

  public override Map<String, Object> buildPayload() {
    return new Map<String, Object>{
      'customField' => customField,
      'triggeredBy' => UserInfo.getName(),
      'timestamp' => Datetime.now().formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'')
    };
  }

  public override Boolean validate() {
    super.validate();

    if (String.isBlank(customField)) {
      throw new GitHubDispatchException('Custom field is required');
    }

    return true;
  }
}
```

#### Step 2: Create GitHub Workflow

Create `.github/workflows/dispatch-custom-event.yml`:

```yaml
name: Custom Event Handler

on:
  repository_dispatch:
    types: [custom_event_type] # Must match getEventType()

jobs:
  handle-custom-event:
    runs-on: ubuntu-latest

    steps:
      - name: Process Event
        run: |
          echo "Custom Field: ${{ github.event.client_payload.customField }}"
          echo "Triggered By: ${{ github.event.client_payload.triggeredBy }}"
```

#### Step 3: Use Your Event

```apex
// Create and dispatch
CustomEvent event = new CustomEvent('my-value');
new GitHubDispatchService().dispatch(event);
```

### Event Types Reference

| Event Type             | Class             | GitHub Workflow            | Purpose             |
| ---------------------- | ----------------- | -------------------------- | ------------------- |
| `deployment_requested` | `DeploymentEvent` | `dispatch-deployment.yml`  | Trigger deployments |
| `test_result`          | `TestResultEvent` | `dispatch-test-result.yml` | Send test results   |
| `data_sync`            | `DataSyncEvent`   | `dispatch-data-sync.yml`   | Sync data           |

### Best Practices

#### 1. Event Naming

- Use snake_case for event types
- Be descriptive: `deployment_requested` not `deploy`
- Match workflow file names: `dispatch-{event-type}.yml`

#### 2. Payload Structure

Always include:

```apex
return new Map<String, Object>{
    // Your fields
    'triggeredBy' => UserInfo.getName(),
    'userId' => UserInfo.getUserId(),
    'timestamp' => Datetime.now().formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'')
};
```

#### 3. Validation

Override `validate()` for business logic:

```apex
public override Boolean validate() {
    super.validate();  // Always call parent

    // Your validation
    if (String.isBlank(requiredField)) {
        throw new GitHubDispatchException('Field is required');
    }

    return true;
}
```

#### 4. Error Handling

```apex
try {
    new GitHubDispatchService().dispatch(event);
} catch (GitHubDispatchEvent.GitHubDispatchException e) {
    System.debug('❌ Dispatch failed: ' + e.getMessage());
    // Handle error (log, notify, retry, etc.)
}
```

#### 5. Repository Configuration

For different repositories:

```apex
GitHubDispatchService dispatcher = new GitHubDispatchService()
    .setRepository('different-owner', 'different-repo');

dispatcher.dispatch(event);
```

### Integration Points

#### From Triggers

```apex
trigger OpportunityTrigger on Opportunity(after update) {
  for (Opportunity opp : Trigger.new) {
    if (
      opp.StageName == 'Closed Won' &&
      Trigger.oldMap.get(opp.Id).StageName != 'Closed Won'
    ) {
      // Dispatch deployment event
      DeploymentEvent event = new DeploymentEvent(
          'production',
          'Opportunity',
          opp.Id
        )
        .setMessage('Opportunity closed - auto-deploy');

      new GitHubDispatchService().dispatch(event);
    }
  }
}
```

#### From Apex Classes

```apex
public class DeploymentService {
  public void triggerDeployment(String environment, Id recordId) {
    DeploymentEvent event = new DeploymentEvent(
      environment,
      recordId.getSObjectType().getDescribe().getName(),
      recordId
    );

    new GitHubDispatchService().dispatch(event);
  }
}
```

#### From Lightning Web Components

Update your LWC to use the framework:

```javascript
import dispatchEvent from '@salesforce/apex/GitHubDispatchService.dispatch';

// In your LWC controller
handleDeploy() {
    const event = {
        eventType: 'deployment_requested',
        environment: this.selectedEnvironment,
        recordType: 'Opportunity',
        recordId: this.recordId
    };

    // Note: You'll need to create an LWC-compatible wrapper
    dispatchEvent({ event })
        .then(() => {
            this.showToast('Success', 'Deployment triggered', 'success');
        })
        .catch(error => {
            this.showToast('Error', error.body.message, 'error');
        });
}
```

### Debugging

Enable debug logs to see dispatch details:

```apex
// Debug logs show:
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// 📤 GitHub Dispatch Event
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Event Type: deployment_requested
// Repository: gforceinnovation/sf-develop-demo
// Response Code: 204
// Payload: {
//   "environment": "staging",
//   "recordType": "Opportunity",
//   ...
// }
```

### Testing

#### Anonymous Apex Testing

```apex
// Test deployment event
DeploymentEvent event = new DeploymentEvent('sandbox', 'Account', '0015000000TEST1')
    .setRunTests(false)
    .setMessage('Test deployment');

Boolean success = new GitHubDispatchService().dispatch(event);
System.debug('Dispatch result: ' + success);
```

#### Unit Tests

```apex
@isTest
private class DeploymentEventTest {
  @isTest
  static void testEventCreation() {
    DeploymentEvent event = new DeploymentEvent(
      'staging',
      'Account',
      '001TEST'
    );

    Test.startTest();
    String eventType = event.getEventType();
    Map<String, Object> payload = event.buildPayload();
    Boolean isValid = event.validate();
    Test.stopTest();

    System.assertEquals('deployment_requested', eventType);
    System.assertEquals('staging', payload.get('environment'));
    System.assertEquals(true, isValid);
  }
}
```

### Monitoring

Check GitHub Actions to see your events:

1. Go to: `https://github.com/{owner}/{repo}/actions`
2. Filter by workflow name
3. View individual run details

### Troubleshooting

| Issue                | Solution                                          |
| -------------------- | ------------------------------------------------- |
| 403 Error            | Check GitHub App has `contents: write` permission |
| Event not triggering | Verify `event_type` matches workflow `types`      |
| Validation fails     | Check required fields are populated               |
| Workflow not found   | Ensure workflow file is pushed to default branch  |

---

**[← Back to Documentation](./README.md)**
