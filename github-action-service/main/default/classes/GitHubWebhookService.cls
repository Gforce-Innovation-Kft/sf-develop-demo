@RestResource(urlMapping='/githubwebhook/*')
global with sharing class GitHubWebhookService {
  @HttpPost
  global static void handleWebhook() {
    RestRequest req = RestContext.request;
    RestResponse res = RestContext.response;

    try {
      // Verify webhook signature
      String signature = req.headers.get('X-Hub-Signature-256');
      String payload = req.requestBody.toString();

      if (!verifySignature(signature, payload)) {
        res.statusCode = 401;
        res.responseBody = Blob.valueOf('{"error": "Invalid signature"}');
        return;
      }

      // Parse webhook payload
      Map<String, Object> webhookData = (Map<String, Object>) JSON.deserializeUntyped(
        payload
      );
      String eventType = req.headers.get('X-GitHub-Event');

      // Handle different event types
      if (eventType == 'workflow_run') {
        handleWorkflowRun(webhookData);
      } else if (eventType == 'workflow_job') {
        handleWorkflowJob(webhookData);
      } else if (eventType == 'ping') {
        System.debug('Received ping event from GitHub');
      } else {
        System.debug('Unhandled event type: ' + eventType);
      }

      res.statusCode = 200;
      res.responseBody = Blob.valueOf('{"status": "success"}');
    } catch (Exception e) {
      System.debug('Webhook error: ' + e.getMessage());
      res.statusCode = 500;
      res.responseBody = Blob.valueOf('{"error": "' + e.getMessage() + '"}');
    }
  }

  private static Boolean verifySignature(String signature, String payload) {
    if (String.isBlank(signature)) {
      return false;
    }

    try {
      // Get webhook secret from Custom Metadata
      List<GitHub_App_Settings__mdt> settingsList = [
        SELECT Webhook_Secret__c
        FROM GitHub_App_Settings__mdt
        WHERE DeveloperName = 'Default'
        LIMIT 1
      ];

      if (
        settingsList.isEmpty() ||
        String.isBlank(settingsList[0].Webhook_Secret__c)
      ) {
        System.debug('Webhook secret not configured');
        return false;
      }

      String secret = settingsList[0].Webhook_Secret__c;
      Blob hmac = Crypto.generateMac(
        'HmacSHA256',
        Blob.valueOf(payload),
        Blob.valueOf(secret)
      );
      String expectedSignature = 'sha256=' + EncodingUtil.convertToHex(hmac);

      return signature.equalsIgnoreCase(expectedSignature);
    } catch (Exception e) {
      System.debug('Signature verification failed: ' + e.getMessage());
      return false;
    }
  }

  private static void handleWorkflowRun(Map<String, Object> data) {
    try {
      Map<String, Object> workflowRun = (Map<String, Object>) data.get(
        'workflow_run'
      );
      String status = (String) workflowRun.get('status');
      String conclusion = (String) workflowRun.get('conclusion');
      String workflowName = (String) workflowRun.get('name');
      Integer runId = (Integer) workflowRun.get('id');

      System.debug(
        'Workflow Run: ' +
          workflowName +
          ' (ID: ' +
          runId +
          ')' +
          ' Status: ' +
          status +
          (conclusion != null ? ', Conclusion: ' + conclusion : '')
      );

      // TODO: Store workflow run information in custom object
      // Example: Create Deployment_Log__c record to track deployments
    } catch (Exception e) {
      System.debug('Error handling workflow_run event: ' + e.getMessage());
    }
  }

  private static void handleWorkflowJob(Map<String, Object> data) {
    try {
      Map<String, Object> workflowJob = (Map<String, Object>) data.get(
        'workflow_job'
      );
      String status = (String) workflowJob.get('status');
      String jobName = (String) workflowJob.get('name');
      Integer jobId = (Integer) workflowJob.get('id');

      System.debug(
        'Workflow Job: ' +
          jobName +
          ' (ID: ' +
          jobId +
          ')' +
          ' Status: ' +
          status
      );

      // TODO: Update deployment log with job status
    } catch (Exception e) {
      System.debug('Error handling workflow_job event: ' + e.getMessage());
    }
  }
}
