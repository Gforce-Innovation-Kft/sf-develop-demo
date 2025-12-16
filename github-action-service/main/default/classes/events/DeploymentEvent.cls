/**
 * @description Deployment event for triggering deployments to different environments
 * Usage:
 *   DeploymentEvent event = new DeploymentEvent('staging', 'Account', '0015000000XXXXX');
 *   new GitHubDispatchService().dispatch(event);
 */
public class DeploymentEvent extends GitHubDispatchEvent {
  private String environment;
  private String recordType;
  private String recordId;
  private Boolean runTests;
  private String message;

  /**
   * @description Constructor with required fields
   */
  public DeploymentEvent(
    String environment,
    String recordType,
    String recordId
  ) {
    this.environment = environment;
    this.recordType = recordType;
    this.recordId = recordId;
    this.runTests = true; // Default
    this.message = 'Deployment triggered from Salesforce';
  }

  /**
   * @description Set optional run tests flag
   */
  public DeploymentEvent setRunTests(Boolean runTests) {
    this.runTests = runTests;
    return this;
  }

  /**
   * @description Set optional message
   */
  public DeploymentEvent setMessage(String message) {
    this.message = message;
    return this;
  }

  public override String getEventType() {
    return 'deployment_requested';
  }

  public override Map<String, Object> buildPayload() {
    return new Map<String, Object>{
      'environment' => environment,
      'recordType' => recordType,
      'recordId' => recordId,
      'runTests' => runTests,
      'message' => message,
      'triggeredBy' => UserInfo.getName(),
      'userId' => UserInfo.getUserId(),
      'timestamp' => Datetime.now().formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'')
    };
  }

  public override Boolean validate() {
    super.validate();

    if (String.isBlank(environment)) {
      throw new GitHubDispatchException('Environment is required');
    }

    List<String> validEnvironments = new List<String>{
      'sandbox',
      'staging',
      'production',
      'qa'
    };
    if (!validEnvironments.contains(environment.toLowerCase())) {
      throw new GitHubDispatchException('Invalid environment: ' + environment);
    }

    if (String.isBlank(recordId)) {
      throw new GitHubDispatchException('Record ID is required');
    }

    return true;
  }
}
