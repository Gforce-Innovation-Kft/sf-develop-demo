/**
 * @description Data sync event for synchronizing Salesforce data to external systems
 * Usage:
 *   DataSyncEvent event = new DataSyncEvent('Account', '0015000000XXXXX')
 *       .addField('Name', 'Acme Corp')
 *       .addField('Industry', 'Technology');
 *   new GitHubDispatchService().dispatch(event);
 */
public class DataSyncEvent extends GitHubDispatchEvent {
  private String recordType;
  private String recordId;
  private Map<String, Object> fields;
  private String operation; // 'create', 'update', 'delete'

  /**
   * @description Constructor with required fields
   */
  public DataSyncEvent(String recordType, String recordId) {
    this.recordType = recordType;
    this.recordId = recordId;
    this.fields = new Map<String, Object>();
    this.operation = 'update'; // Default
  }

  /**
   * @description Add a field to sync
   */
  public DataSyncEvent addField(String fieldName, Object fieldValue) {
    this.fields.put(fieldName, fieldValue);
    return this;
  }

  /**
   * @description Set operation type
   */
  public DataSyncEvent setOperation(String operation) {
    this.operation = operation;
    return this;
  }

  public override String getEventType() {
    return 'data_sync';
  }

  public override Map<String, Object> buildPayload() {
    return new Map<String, Object>{
      'recordType' => recordType,
      'recordId' => recordId,
      'operation' => operation,
      'fields' => fields,
      'triggeredBy' => UserInfo.getName(),
      'timestamp' => Datetime.now().formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'')
    };
  }

  public override Boolean validate() {
    super.validate();

    if (String.isBlank(recordType)) {
      throw new GitHubDispatchException('Record type is required');
    }

    if (String.isBlank(recordId)) {
      throw new GitHubDispatchException('Record ID is required');
    }

    List<String> validOperations = new List<String>{
      'create',
      'update',
      'delete'
    };
    if (!validOperations.contains(operation.toLowerCase())) {
      throw new GitHubDispatchException('Invalid operation: ' + operation);
    }

    return true;
  }
}
