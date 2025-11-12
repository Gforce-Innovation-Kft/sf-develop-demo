/**
 * Lightning Web Component controller for Weather Dashboard
 */
public with sharing class WeatherDashboardController {
    
    /**
     * Get current weather and save to database
     */
    @AuraEnabled
    public static Map<String, Object> getCurrentWeatherAndSave(String city) {
        try {
            // Get weather service from factory
            IWeatherService weatherService = (IWeatherService) Application.Service.newInstance(IWeatherService.class);
            
            // Get current weather data
            WeatherData weatherData = weatherService.getCurrentWeather(city);
            
            // Save to database
            Id reportId = weatherService.saveWeatherReport(weatherData);
            
            // Return response
            return new Map<String, Object> {
                'success' => true,
                'weatherData' => formatWeatherDataForUI(weatherData),
                'reportId' => reportId,
                'message' => 'Weather data retrieved and saved successfully'
            };
            
        } catch (Exception e) {
            System.debug('Error in getCurrentWeatherAndSave: ' + e.getMessage());
            return new Map<String, Object> {
                'success' => false,
                'error' => e.getMessage(),
                'message' => 'Failed to get weather data: ' + e.getMessage()
            };
        }
    }
    
    /**
     * Get weather reports for a city
     */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getWeatherReports(String city, Integer limitCount) {
        try {
            // Get weather service from factory
            IWeatherService weatherService = (IWeatherService) Application.Service.newInstance(IWeatherService.class);
            
            // Get weather reports
            List<Weather_Report__c> reports = weatherService.getWeatherReports(city, limitCount);
            
            // Format for UI
            List<Map<String, Object>> formattedReports = new List<Map<String, Object>>();
            for (Weather_Report__c report : reports) {
                formattedReports.add(formatReportForUI(report));
            }
            
            return formattedReports;
            
        } catch (Exception e) {
            System.debug('Error in getWeatherReports: ' + e.getMessage());
            throw new AuraHandledException('Failed to get weather reports: ' + e.getMessage());
        }
    }
    
    /**
     * Get recent weather reports across all cities
     */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getRecentWeatherReports(Integer limitCount) {
        try {
            // Get recent reports using selector
            List<Weather_Report__c> reports = WeatherReportsSelector.newInstance()
                .selectRecentReports(limitCount);
            
            // Format for UI
            List<Map<String, Object>> formattedReports = new List<Map<String, Object>>();
            for (Weather_Report__c report : reports) {
                formattedReports.add(formatReportForUI(report));
            }
            
            return formattedReports;
            
        } catch (Exception e) {
            System.debug('Error in getRecentWeatherReports: ' + e.getMessage());
            throw new AuraHandledException('Failed to get recent weather reports: ' + e.getMessage());
        }
    }
    
    /**
     * Delete weather report
     */
    @AuraEnabled
    public static Map<String, Object> deleteWeatherReport(Id reportId) {
        try {
            // Create Unit of Work
            fflib_ISObjectUnitOfWork uow = Application.UnitOfWork.newInstance();
            
            // Get report to delete
            Weather_Report__c reportToDelete = new Weather_Report__c(Id = reportId);
            
            // Register for deletion
            uow.registerDeleted(reportToDelete);
            
            // Commit changes
            uow.commitWork();
            
            return new Map<String, Object> {
                'success' => true,
                'message' => 'Weather report deleted successfully'
            };
            
        } catch (Exception e) {
            System.debug('Error in deleteWeatherReport: ' + e.getMessage());
            return new Map<String, Object> {
                'success' => false,
                'error' => e.getMessage(),
                'message' => 'Failed to delete weather report: ' + e.getMessage()
            };
        }
    }
    
    /**
     * Format weather data for UI consumption
     */
    private static Map<String, Object> formatWeatherDataForUI(WeatherData weatherData) {
        return new Map<String, Object> {
            'city' => weatherData.city,
            'temperature' => weatherData.temperature,
            'temperatureFormatted' => weatherData.temperature + '°C',
            'description' => weatherData.description,
            'humidity' => weatherData.humidity,
            'humidityFormatted' => weatherData.humidity + '%',
            'pressure' => weatherData.pressure,
            'pressureFormatted' => weatherData.pressure + ' hPa',
            'reportDateTime' => weatherData.reportDateTime,
            'reportDateTimeFormatted' => weatherData.reportDateTime?.format('MMM dd, yyyy HH:mm')
        };
    }
    
    /**
     * Format weather report for UI consumption
     */
    private static Map<String, Object> formatReportForUI(Weather_Report__c report) {
        return new Map<String, Object> {
            'id' => report.Id,
            'name' => report.Name,
            'city' => report.City__c,
            'temperature' => report.Temperature__c,
            'temperatureFormatted' => report.Temperature__c + '°C',
            'description' => report.Weather_Description__c,
            'humidity' => report.Humidity__c,
            'humidityFormatted' => report.Humidity__c + '%',
            'pressure' => report.Pressure__c,
            'pressureFormatted' => report.Pressure__c + ' hPa',
            'reportDateTime' => report.Report_Date_Time__c,
            'reportDateTimeFormatted' => report.Report_Date_Time__c?.format('MMM dd, yyyy HH:mm'),
            'createdDate' => report.CreatedDate,
            'createdDateFormatted' => report.CreatedDate?.format('MMM dd, yyyy HH:mm')
        };
    }
}