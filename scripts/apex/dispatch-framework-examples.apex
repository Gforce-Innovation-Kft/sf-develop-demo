// ============================================================================
// Example: Using the GitHub Dispatch Event Framework
// ============================================================================
// Copy these examples to test the dispatch framework
// ============================================================================

System.debug('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
System.debug('🚀 GitHub Dispatch Event Framework Examples');
System.debug('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

// ============================================================================
// Example 1: Simple Deployment Event
// ============================================================================
System.debug('');
System.debug('Example 1: Trigger Deployment to Staging');
System.debug('─────────────────────────────────────────');

DeploymentEvent deployEvent = new DeploymentEvent('staging', 'Opportunity', '0065000000XXXXX')
    .setRunTests(true)
    .setMessage('Opportunity closed - deploying to staging');

Boolean deploySuccess = new GitHubDispatchService().dispatch(deployEvent);
System.debug('Deployment dispatched: ' + deploySuccess);

// ============================================================================
// Example 2: Test Result Event
// ============================================================================
System.debug('');
System.debug('Example 2: Send Test Results (Failure)');
System.debug('─────────────────────────────────────────');

TestResultEvent testEvent = new TestResultEvent(false, 'AccountTriggerTest', 72.5)
    .setMessage('CPU time limit exceeded')
    .setErrorDetails('System.LimitException: Apex CPU time limit exceeded at line 45');

Boolean testSuccess = new GitHubDispatchService().dispatch(testEvent);
System.debug('Test result dispatched: ' + testSuccess);

// ============================================================================
// Example 3: Data Sync Event
// ============================================================================
System.debug('');
System.debug('Example 3: Sync Account Data');
System.debug('─────────────────────────────────────────');

DataSyncEvent syncEvent = new DataSyncEvent('Account', '0015000000XXXXX')
    .setOperation('update')
    .addField('Name', 'Acme Corporation')
    .addField('Industry', 'Technology')
    .addField('AnnualRevenue', 5000000)
    .addField('Phone', '555-1234');

Boolean syncSuccess = new GitHubDispatchService().dispatch(syncEvent);
System.debug('Data sync dispatched: ' + syncSuccess);

// ============================================================================
// Example 4: Batch Dispatch (Multiple Events)
// ============================================================================
System.debug('');
System.debug('Example 4: Batch Dispatch Multiple Events');
System.debug('─────────────────────────────────────────');

List<GitHubDispatchEvent> events = new List<GitHubDispatchEvent>{
    new DeploymentEvent('sandbox', 'Account', '0015000000TEST1')
        .setRunTests(false),

    new TestResultEvent(true, 'OpportunityTest', 88.5)
        .setMessage('All tests passed'),

    new DataSyncEvent('Contact', '0035000000TEST2')
        .setOperation('create')
        .addField('FirstName', 'John')
        .addField('LastName', 'Doe')
        .addField('Email', 'john.doe@example.com')
};

Map<String, Boolean> batchResults = new GitHubDispatchService().dispatchBatch(events);

System.debug('Batch dispatch results:');
for (String eventType : batchResults.keySet()) {
    System.debug('  ' + eventType + ': ' + (batchResults.get(eventType) ? '✅' : '❌'));
}

// ============================================================================
// Example 5: Custom Repository
// ============================================================================
System.debug('');
System.debug('Example 5: Dispatch to Different Repository');
System.debug('─────────────────────────────────────────');

GitHubDispatchService customDispatcher = new GitHubDispatchService()
    .setRepository('different-org', 'different-repo');

DeploymentEvent customEvent = new DeploymentEvent('production', 'Case', '5005000000XXXXX')
    .setMessage('Critical case - emergency deployment');

Boolean customSuccess = customDispatcher.dispatch(customEvent);
System.debug('Custom repository dispatch: ' + customSuccess);

// ============================================================================
// Example 6: Error Handling
// ============================================================================
System.debug('');
System.debug('Example 6: Error Handling');
System.debug('─────────────────────────────────────────');

try {
    // This will fail validation (empty environment)
    DeploymentEvent invalidEvent = new DeploymentEvent('', 'Account', '001...');
    new GitHubDispatchService().dispatch(invalidEvent);
} catch (GitHubDispatchEvent.GitHubDispatchException e) {
    System.debug('❌ Caught validation error: ' + e.getMessage());
}

try {
    // This will fail validation (invalid environment)
    DeploymentEvent invalidEnv = new DeploymentEvent('invalid-env', 'Account', '001...');
    new GitHubDispatchService().dispatch(invalidEnv);
} catch (GitHubDispatchEvent.GitHubDispatchException e) {
    System.debug('❌ Caught validation error: ' + e.getMessage());
}

// ============================================================================
// Example 7: Using in Real Scenario - After Opportunity Closes
// ============================================================================
System.debug('');
System.debug('Example 7: Real Scenario - Opportunity Workflow');
System.debug('─────────────────────────────────────────');

// Simulate closed opportunity
Id opportunityId = '0065000000XXXXX'; // Replace with real ID
String opportunityName = 'Acme Corp - 100 Licenses';

// Create deployment event
DeploymentEvent oppDeployEvent = new DeploymentEvent('production', 'Opportunity', opportunityId)
    .setRunTests(true)
    .setMessage('Opportunity "' + opportunityName + '" closed won - deploying new configuration');

// Create data sync event
DataSyncEvent oppSyncEvent = new DataSyncEvent('Opportunity', opportunityId)
    .setOperation('update')
    .addField('Name', opportunityName)
    .addField('StageName', 'Closed Won')
    .addField('Amount', 100000);

// Dispatch both
List<GitHubDispatchEvent> oppEvents = new List<GitHubDispatchEvent>{
    oppDeployEvent,
    oppSyncEvent
};

Map<String, Boolean> oppResults = new GitHubDispatchService().dispatchBatch(oppEvents);
System.debug('Opportunity workflow complete:');
System.debug('  Deployment: ' + (oppResults.get('deployment_requested') ? '✅' : '❌'));
System.debug('  Data Sync: ' + (oppResults.get('data_sync') ? '✅' : '❌'));

System.debug('');
System.debug('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
System.debug('✅ All examples complete!');
System.debug('');
System.debug('📝 Next steps:');
System.debug('  1. Check GitHub Actions tab for workflow runs');
System.debug('  2. Review debug logs above for details');
System.debug('  3. Create your own custom events!');
System.debug('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

