# Weather Dashboard Demo - Apex Enterprise Patterns

This demo application showcases Apex Enterprise Patterns with a real-world integration to the OpenWeatherMap API.

## Features

- **Domain Layer**: Weather Report domain logic with validation
- **Service Layer**: Weather service with external API integration
- **Selector Layer**: Data access patterns for Weather Reports
- **Unit of Work**: Transactional integrity for database operations
- **Lightning Web Component**: Modern UI for weather dashboard
- **External API Integration**: Free OpenWeatherMap API integration

## Architecture

The application follows Martin Fowler's Enterprise Patterns as implemented in the fflib-apex-common library:

```
┌─────────────────┐
│   Lightning     │
│ Web Component   │
└─────────────────┘
         │
┌─────────────────┐
│   Controller    │
│     Layer       │
└─────────────────┘
         │
┌─────────────────┐
│   Service       │
│     Layer       │
└─────────────────┘
         │
┌─────────────────┬─────────────────┐
│   Domain        │   Selector      │
│    Layer        │     Layer       │
└─────────────────┴─────────────────┘
         │
┌─────────────────┐
│ Unit of Work    │
│ & Data Layer    │
└─────────────────┘
```

## Setup Instructions

### 1. Get OpenWeatherMap API Key
1. Go to [OpenWeatherMap](https://openweathermap.org/api)
2. Sign up for a free account
3. Get your API key from the dashboard
4. Replace `YOUR_API_KEY_HERE` in `WeatherServiceImpl.cls` with your actual API key

### 2. Deploy to Salesforce
```bash
# Deploy the application
sfdx force:source:deploy -p force-app -u [your-org-alias]

# Or push to scratch org
sfdx force:source:push -u [your-scratch-org]
```

### 3. Assign Permissions
1. Navigate to Setup → Permission Sets
2. Create or edit a permission set to include:
   - Read/Write access to Weather_Report__c object
   - Access to WeatherDashboardController class

### 4. Add Remote Site Setting
The deployment includes a Remote Site Setting for `https://api.openweathermap.org`

### 5. Access the Dashboard
1. Navigate to App Launcher
2. Find "Weather Dashboard" tab
3. Or add the Weather Dashboard Lightning component to any Lightning page

## Usage

1. Enter a city name (e.g., "London", "New York", "Tokyo")
2. Click "Get Current Weather"
3. View current weather data and saved reports
4. Browse historical weather data in the reports table

## Components

### Custom Objects
- **Weather_Report__c**: Stores weather data with fields for temperature, humidity, pressure, etc.

### Apex Classes
- **Application.cls**: Application factory configuration
- **IWeatherService.cls**: Service interface
- **WeatherServiceImpl.cls**: Service implementation with API integration
- **WeatherData.cls**: Data transfer object
- **WeatherReports.cls**: Domain class with business logic
- **WeatherReportsSelector.cls**: Data access layer
- **WeatherDashboardController.cls**: Lightning component controller

### Lightning Web Component
- **weatherDashboard**: Modern UI component with search, display, and management features

### Metadata
- Remote Site Setting for OpenWeatherMap API
- Lightning Tab and App Page for easy access

## Enterprise Patterns Demonstrated

1. **Application Factory**: Centralized configuration for all layers
2. **Service Layer**: Business logic and external integrations
3. **Domain Layer**: Entity-specific business rules and validation  
4. **Selector Layer**: Consistent data access patterns
5. **Unit of Work**: Transactional integrity and bulk processing
6. **Dependency Injection**: Loose coupling through interfaces

## API Integration

This demo uses the OpenWeatherMap Current Weather Data API:
- **Endpoint**: `https://api.openweathermap.org/data/2.5/weather`
- **Free Tier**: 1,000 calls/day
- **No Credit Card Required**

## Testing

Each layer includes comprehensive test coverage following Apex Enterprise Patterns testing strategies.

## Next Steps

- Add more weather APIs (forecast, historical data)
- Implement caching strategies
- Add batch processing for multiple cities
- Create mobile-optimized views
- Add data visualization charts