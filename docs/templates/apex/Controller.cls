public with sharing class {{ControllerName}} {
    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getItems(String searchTerm, Integer limitCount) {
        {{ServiceInterface}} service = ({{ServiceInterface}}) Application.Service.newInstance({{ServiceInterface}}.class);
        List<{{SObjectName}}> records = service.{{readMethod}}(searchTerm, limitCount);

        List<Map<String, Object>> response = new List<Map<String, Object>>();
        for ({{SObjectName}} recordItem : records) {
            response.add(new Map<String, Object> {
                'id' => recordItem.Id,
                'name' => recordItem.Name
            });
        }
        return response;
    }

    @AuraEnabled
    public static Map<String, Object> saveItem({{InputType}} inputData) {
        {{ServiceInterface}} service = ({{ServiceInterface}}) Application.Service.newInstance({{ServiceInterface}}.class);
        Id recordId = service.{{writeMethod}}(inputData);
        return new Map<String, Object> {
            'success' => true,
            'recordId' => recordId
        };
    }
}
