/**
 * Domain class for Weather Report records following Enterprise Patterns
 */
public class WeatherReports extends fflib_SObjectDomain {
    
    public WeatherReports(List<Weather_Report__c> sObjectList) {
        super(sObjectList);
    }
    
    public class Constructor implements fflib_SObjectDomain.IConstructable {
        public fflib_SObjectDomain construct(List<SObject> sObjectList) {
            return new WeatherReports(sObjectList);
        }
    }
    
    /**
     * Domain logic for validating weather reports
     */
    public override void onBeforeInsert() {
        validateWeatherReports();
        setReportDateTime();
    }
    
    public override void onBeforeUpdate(Map<Id, SObject> existingRecords) {
        validateWeatherReports();
    }
    
    /**
     * Validate weather report data
     */
    private void validateWeatherReports() {
        for (Weather_Report__c report : getWeatherRecords()) {
            validateTemperature(report);
            validateHumidity(report);
            validateCity(report);
        }
    }
    
    /**
     * Set report date time for new records
     */
    private void setReportDateTime() {
        for (Weather_Report__c report : getWeatherRecords()) {
            if (report.Report_Date_Time__c == null) {
                report.Report_Date_Time__c = System.now();
            }
        }
    }
    
    /**
     * Validate temperature is within reasonable range
     */
    private void validateTemperature(Weather_Report__c report) {
        if (report.Temperature__c != null && 
            (report.Temperature__c < -100 || report.Temperature__c > 70)) {
            report.Temperature__c.addError('Temperature must be between -100°C and 70°C');
        }
    }
    
    /**
     * Validate humidity percentage
     */
    private void validateHumidity(Weather_Report__c report) {
        if (report.Humidity__c != null && 
            (report.Humidity__c < 0 || report.Humidity__c > 100)) {
            report.Humidity__c.addError('Humidity must be between 0% and 100%');
        }
    }
    
    /**
     * Validate city name is not empty
     */
    private void validateCity(Weather_Report__c report) {
        if (String.isBlank(report.City__c)) {
            report.City__c.addError('City name is required');
        }
    }
    
    /**
     * Get typed records
     */
    public override List<SObject> getRecords() {
        return Records;
    }
    
    /**
     * Get typed records as Weather Reports
     */
    private List<Weather_Report__c> getWeatherRecords() {
        return (List<Weather_Report__c>) Records;
    }
    
    /**
     * Filter records by city
     */
    public List<Weather_Report__c> selectByCity(String city) {
        List<Weather_Report__c> result = new List<Weather_Report__c>();
        for (Weather_Report__c report : getWeatherRecords()) {
            if (report.City__c?.equalsIgnoreCase(city)) {
                result.add(report);
            }
        }
        return result;
    }
    
    /**
     * Filter records by temperature range
     */
    public List<Weather_Report__c> selectByTemperatureRange(Decimal minTemp, Decimal maxTemp) {
        List<Weather_Report__c> result = new List<Weather_Report__c>();
        for (Weather_Report__c report : getWeatherRecords()) {
            if (report.Temperature__c != null && 
                report.Temperature__c >= minTemp && 
                report.Temperature__c <= maxTemp) {
                result.add(report);
            }
        }
        return result;
    }
}