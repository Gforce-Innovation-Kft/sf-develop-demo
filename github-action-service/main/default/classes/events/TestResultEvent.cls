/**
 * @description Test result event for sending Apex test results to GitHub
 * Usage:
 *   TestResultEvent event = new TestResultEvent(true, 'AccountTriggerTest', 85.5);
 *   new GitHubDispatchService().dispatch(event);
 */
public class TestResultEvent extends GitHubDispatchEvent {
  private Boolean passed;
  private String testSuite;
  private Decimal coverage;
  private String message;
  private String errorDetails;

  /**
   * @description Constructor with required fields
   */
  public TestResultEvent(Boolean passed, String testSuite, Decimal coverage) {
    this.passed = passed;
    this.testSuite = testSuite;
    this.coverage = coverage;
    this.message = passed ? 'All tests passed' : 'Tests failed';
  }

  /**
   * @description Set error details for failed tests
   */
  public TestResultEvent setErrorDetails(String errorDetails) {
    this.errorDetails = errorDetails;
    return this;
  }

  /**
   * @description Set custom message
   */
  public TestResultEvent setMessage(String message) {
    this.message = message;
    return this;
  }

  public override String getEventType() {
    return 'test_result';
  }

  public override Map<String, Object> buildPayload() {
    Map<String, Object> payload = new Map<String, Object>{
      'passed' => passed,
      'testSuite' => testSuite,
      'coverage' => coverage,
      'message' => message,
      'triggeredBy' => UserInfo.getName(),
      'timestamp' => Datetime.now().formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'')
    };

    if (String.isNotBlank(errorDetails)) {
      payload.put('errorDetails', errorDetails);
    }

    return payload;
  }

  public override Boolean validate() {
    super.validate();

    if (coverage < 0 || coverage > 100) {
      throw new GitHubDispatchException('Coverage must be between 0 and 100');
    }

    return true;
  }
}
