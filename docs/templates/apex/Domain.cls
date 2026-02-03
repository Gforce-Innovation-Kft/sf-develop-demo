public with sharing class {{DomainName}} extends fflib_SObjectDomain {
    public {{DomainName}}(List<{{SObjectName}}> records) {
        super(records);
    }

    public class Constructor implements fflib_SObjectDomain.IConstructable {
        public fflib_SObjectDomain construct(List<SObject> sObjectList) {
            return new {{DomainName}}(sObjectList);
        }
    }

    public override void onBeforeInsert() {
        validateRecords();
    }

    public override void onBeforeUpdate(Map<Id, SObject> existingRecords) {
        validateRecords();
    }

    private void validateRecords() {
        for ({{SObjectName}} recordItem : getTypedRecords()) {
            // TODO: add validations
        }
    }

    private List<{{SObjectName}}> getTypedRecords() {
        return (List<{{SObjectName}}>) Records;
    }
}
