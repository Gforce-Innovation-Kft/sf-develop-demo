/**
 * Weather Service implementation using OpenWeatherMap API
 * Following Enterprise Patterns service layer
 */
public class WeatherServiceImpl implements IWeatherService {
    
    private static final String API_BASE_URL = 'https://api.openweathermap.org/data/2.5/weather';
    private static final String API_KEY = 'e3dae87915d38f430c4ab7650cd76e59'; // Replace with actual API key
    
    /**
     * Get current weather data from OpenWeatherMap API
     */
    public WeatherData getCurrentWeather(String city) {
        try {
            // Build API URL
            String apiUrl = API_BASE_URL + 
                           '?q=' + EncodingUtil.urlEncode(city, 'UTF-8') +
                           '&appid=' + API_KEY +
                           '&units=metric'; // Use Celsius
            
            // Make HTTP callout
            Http http = new Http();
            HttpRequest request = new HttpRequest();
            request.setEndpoint(apiUrl);
            request.setMethod('GET');
            request.setTimeout(10000); // 10 second timeout
            
            HttpResponse response = http.send(request);
            
            if (response.getStatusCode() == 200) {
                return parseWeatherResponse(response.getBody(), city);
            } else {
                throw new WeatherServiceException('API call failed: ' + response.getStatus());
            }
            
        } catch (Exception e) {
            System.debug('Error in getCurrentWeather: ' + e.getMessage());
            throw new WeatherServiceException('Failed to get weather data: ' + e.getMessage());
        }
    }
    
    /**
     * Save weather report to database using Unit of Work pattern
     */
    public Id saveWeatherReport(WeatherData weatherData) {
        try {
            // Create Unit of Work
            fflib_ISObjectUnitOfWork uow = Application.UnitOfWork.newInstance();
            
            // Create Weather Report record
            Weather_Report__c report = new Weather_Report__c(
                City__c = weatherData.city,
                Temperature__c = weatherData.temperature,
                Weather_Description__c = weatherData.description,
                Humidity__c = weatherData.humidity,
                Pressure__c = weatherData.pressure,
                Report_Date_Time__c = weatherData.reportDateTime
            );
            
            // Register for insert
            uow.registerNew(report);
            
            // Commit changes
            uow.commitWork();
            
            return report.Id;
            
        } catch (Exception e) {
            System.debug('Error in saveWeatherReport: ' + e.getMessage());
            throw new WeatherServiceException('Failed to save weather report: ' + e.getMessage());
        }
    }
    
    /**
     * Get weather reports for a city using Selector pattern
     */
    public List<Weather_Report__c> getWeatherReports(String city, Integer limitCount) {
        try {
            return WeatherReportsSelector.newInstance()
                .selectByCity(city, limitCount);
        } catch (Exception e) {
            System.debug('Error in getWeatherReports: ' + e.getMessage());
            throw new WeatherServiceException('Failed to get weather reports: ' + e.getMessage());
        }
    }
    
    /**
     * Parse JSON response from OpenWeatherMap API
     */
    private WeatherData parseWeatherResponse(String jsonResponse, String city) {
        try {
            Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(jsonResponse);
            
            WeatherData weatherData = new WeatherData(city);
            
            // Parse main weather data
            Map<String, Object> main = (Map<String, Object>) responseMap.get('main');
            if (main != null) {
                weatherData.temperature = (Decimal) main.get('temp');
                weatherData.humidity = (Decimal) main.get('humidity');
                weatherData.pressure = (Decimal) main.get('pressure');
            }
            
            // Parse weather description
            List<Object> weather = (List<Object>) responseMap.get('weather');
            if (weather != null && !weather.isEmpty()) {
                Map<String, Object> weatherInfo = (Map<String, Object>) weather[0];
                weatherData.description = (String) weatherInfo.get('description');
            }
            
            return weatherData;
            
        } catch (Exception e) {
            System.debug('Error parsing weather response: ' + e.getMessage());
            throw new WeatherServiceException('Failed to parse weather data: ' + e.getMessage());
        }
    }
    
    /**
     * Custom exception for weather service errors
     */
    public class WeatherServiceException extends Exception {}
}