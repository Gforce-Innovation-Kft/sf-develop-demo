/**
 * Service interface for weather operations following Enterprise Patterns
 */
public interface IWeatherService {
    /**
     * Get current weather for a city
     */
    WeatherData getCurrentWeather(String city);
    
    /**
     * Save weather report to database
     */
    Id saveWeatherReport(WeatherData weatherData);
    
    /**
     * Get weather reports for a city
     */
    List<Weather_Report__c> getWeatherReports(String city, Integer limitCount);
}