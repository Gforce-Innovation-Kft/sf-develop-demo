/**
 * Application factory configuration following Enterprise Patterns
 */
public class Application {
    
    // Configure Unit of Work factory
    public static final fflib_Application.UnitOfWorkFactory UnitOfWork = 
        new fflib_Application.UnitOfWorkFactory(
            new List<SObjectType> {
                Weather_Report__c.SObjectType
            });
    
    // Configure Service factory  
    public static final fflib_Application.ServiceFactory Service =
        new fflib_Application.ServiceFactory(
            new Map<Type, Type> {
                IWeatherService.class => WeatherServiceImpl.class
            });
    
    // Configure Selector factory
    public static final fflib_Application.SelectorFactory Selector =
        new fflib_Application.SelectorFactory(
            new Map<SObjectType, Type> {
                Weather_Report__c.SObjectType => WeatherReportsSelector.class
            });
    
    // Configure Domain factory
    public static final fflib_Application.DomainFactory Domain =
        new fflib_Application.DomainFactory(
            Application.Selector,
            new Map<SObjectType, Type> {
                Weather_Report__c.SObjectType => WeatherReports.Constructor.class
            });
}