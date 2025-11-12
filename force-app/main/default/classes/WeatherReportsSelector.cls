/**
 * Selector class for Weather Reports following Enterprise Patterns
 */
public class WeatherReportsSelector extends fflib_SObjectSelector {
    
    /**
     * Get singleton instance
     */
    public static WeatherReportsSelector newInstance() {
        return (WeatherReportsSelector) Application.Selector.newInstance(Weather_Report__c.SObjectType);
    }
    
    /**
     * Get SObject type
     */
    public Schema.SObjectType getSObjectType() {
        return Weather_Report__c.SObjectType;
    }
    
    /**
     * Get default field set
     */
    public List<Schema.SObjectField> getSObjectFieldList() {
        return new List<Schema.SObjectField> {
            Weather_Report__c.Id,
            Weather_Report__c.Name,
            Weather_Report__c.City__c,
            Weather_Report__c.Temperature__c,
            Weather_Report__c.Weather_Description__c,
            Weather_Report__c.Humidity__c,
            Weather_Report__c.Pressure__c,
            Weather_Report__c.Report_Date_Time__c,
            Weather_Report__c.CreatedDate,
            Weather_Report__c.LastModifiedDate
        };
    }
    
    /**
     * Select records by IDs
     */
    public List<Weather_Report__c> selectById(Set<Id> idSet) {
        return (List<Weather_Report__c>) selectSObjectsById(idSet);
    }
    
    /**
     * Select records by city
     */
    public List<Weather_Report__c> selectByCity(String city) {
        return selectByCity(city, null);
    }
    
    /**
     * Select records by city with limit
     */
    public List<Weather_Report__c> selectByCity(String city, Integer limitCount) {
        fflib_QueryFactory queryFactory = newQueryFactory();
        queryFactory.setCondition('City__c = :city');
        queryFactory.addOrdering('Report_Date_Time__c', fflib_QueryFactory.SortOrder.DESCENDING);
        
        if (limitCount != null && limitCount > 0) {
            queryFactory.setLimit(limitCount);
        }
        
        return (List<Weather_Report__c>) Database.query(queryFactory.toSOQL());
    }
    
    /**
     * Select recent reports across all cities
     */
    public List<Weather_Report__c> selectRecentReports(Integer limitCount) {
        fflib_QueryFactory queryFactory = newQueryFactory();
        queryFactory.addOrdering('Report_Date_Time__c', fflib_QueryFactory.SortOrder.DESCENDING);
        
        if (limitCount != null && limitCount > 0) {
            queryFactory.setLimit(limitCount);
        }
        
        return (List<Weather_Report__c>) Database.query(queryFactory.toSOQL());
    }
    
    /**
     * Select reports by temperature range
     */
    public List<Weather_Report__c> selectByTemperatureRange(Decimal minTemp, Decimal maxTemp) {
        fflib_QueryFactory queryFactory = newQueryFactory();
        queryFactory.setCondition('Temperature__c >= :minTemp AND Temperature__c <= :maxTemp');
        queryFactory.addOrdering('Temperature__c', fflib_QueryFactory.SortOrder.ASCENDING);
        
        return (List<Weather_Report__c>) Database.query(queryFactory.toSOQL());
    }
    
    /**
     * Select reports by date range
     */
    public List<Weather_Report__c> selectByDateRange(DateTime startDate, DateTime endDate) {
        fflib_QueryFactory queryFactory = newQueryFactory();
        queryFactory.setCondition('Report_Date_Time__c >= :startDate AND Report_Date_Time__c <= :endDate');
        queryFactory.addOrdering('Report_Date_Time__c', fflib_QueryFactory.SortOrder.DESCENDING);
        
        return (List<Weather_Report__c>) Database.query(queryFactory.toSOQL());
    }
}