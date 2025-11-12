/**
 * Weather data wrapper class
 */
public class WeatherData {
    public String city { get; set; }
    public Decimal temperature { get; set; }
    public String description { get; set; }
    public Decimal humidity { get; set; }
    public Decimal pressure { get; set; }
    public DateTime reportDateTime { get; set; }
    
    public WeatherData() {
        this.reportDateTime = System.now();
    }
    
    public WeatherData(String city) {
        this();
        this.city = city;
    }
}