public with sharing class {{SelectorName}} extends fflib_SObjectSelector {
    public static {{SelectorName}} newInstance() {
        return ({{SelectorName}}) Application.Selector.newInstance({{SObjectName}}.SObjectType);
    }

    public Schema.SObjectType getSObjectType() {
        return {{SObjectName}}.SObjectType;
    }

    public List<Schema.SObjectField> getSObjectFieldList() {
        return new List<Schema.SObjectField> {
            {{SObjectName}}.Id
            // TODO: add fields
        };
    }

    public List<{{SObjectName}}> selectById(Set<Id> idSet) {
        return (List<{{SObjectName}}>) selectSObjectsById(idSet);
    }

    public List<{{SObjectName}}> selectByField(String value) {
        fflib_QueryFactory queryFactory = newQueryFactory();
        queryFactory.setCondition('Field__c = :value');
        return (List<{{SObjectName}}>) Database.query(queryFactory.toSOQL());
    }
}
