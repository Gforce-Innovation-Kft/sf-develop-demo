/**
 * @description       : 
 * @author            : Gabor Demeter
 * @group             : 
 * @last modified on  : 08-05-2026
 * @last modified by  : Gabor Demeter
**/
/**
 * @description Abstract base class for GitHub repository dispatch events
 * Provides common structure and validation for all dispatch events
 */
public abstract class GitHubDispatchEvent {
  /**
   * @description The event type identifier (must match GitHub workflow types)
   * Example: 'salesforce_event', 'deployment_complete', 'test_result'
   */
  public abstract String getEventType();

  /**
   * @description Build the client payload for this event
   * @return Map of key-value pairs to send in the dispatch event
   */
  public abstract Map<String, Object> buildPayload();

  /**
   * @description Validate the event before dispatching
   * @return True if valid, throws exception if not
   */
  public virtual Boolean validate() {
    if (String.isBlank(getEventType())) {
      throw new GitHubDispatchException('Event type cannot be blank');
    }
    return true;
  }

  /**
   * @description Get metadata about this event (for logging/debugging)
   */
  public virtual Map<String, Object> getMetadata() {
    return new Map<String, Object>{
      'eventType' => getEventType(),
      'timestamp' => Datetime.now().formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\''),
      'triggeredBy' => UserInfo.getUserName(),
      'userId' => UserInfo.getUserId(),
      'orgId' => UserInfo.getOrganizationId()
    };
  }

  /**
   * @description Convert event to JSON representation
   */
  public virtual String toJson() {
    Map<String, Object> fullPayload = new Map<String, Object>{
      'event_type' => getEventType(),
      'client_payload' => buildPayload()
    };
    return JSON.serialize(fullPayload);
  }

  /**
   * Custom exception for dispatch events
   */
  public class GitHubDispatchException extends Exception {
  }
}
