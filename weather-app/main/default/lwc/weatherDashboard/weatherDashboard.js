import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getCurrentWeatherAndSave from '@salesforce/apex/WeatherDashboardController.getCurrentWeatherAndSave';
import getWeatherReports from '@salesforce/apex/WeatherDashboardController.getWeatherReports';
import getRecentWeatherReports from '@salesforce/apex/WeatherDashboardController.getRecentWeatherReports';
import deleteWeatherReport from '@salesforce/apex/WeatherDashboardController.deleteWeatherReport';

export default class WeatherDashboard extends LightningElement {
    @track cityName = '';
    @track currentWeather = null;
    @track weatherReports = [];
    @track recentReports = [];
    @track isLoading = false;
    @track showCurrentWeather = false;
    @track showReports = false;

    // Wired methods for reactive data
    wiredRecentReports;
    wiredCityReports;

    @wire(getRecentWeatherReports, { limitCount: 10 })
    wiredGetRecentReports(result) {
        this.wiredRecentReports = result;
        if (result.data) {
            this.recentReports = result.data;
        } else if (result.error) {
            this.showToast('Error', 'Failed to load recent reports: ' + result.error.body.message, 'error');
        }
    }

    @wire(getWeatherReports, { city: '$cityName', limitCount: 5 })
    wiredGetWeatherReports(result) {
        this.wiredCityReports = result;
        if (result.data && this.cityName) {
            this.weatherReports = result.data;
            this.showReports = true;
        } else if (result.error && this.cityName) {
            this.showToast('Error', 'Failed to load weather reports: ' + result.error.body.message, 'error');
        }
    }

    // Handle city name input
    handleCityNameChange(event) {
        this.cityName = event.target.value;
        this.showReports = false;
        this.showCurrentWeather = false;
    }

    // Get current weather
    async handleGetWeather() {
        if (!this.cityName.trim()) {
            this.showToast('Error', 'Please enter a city name', 'error');
            return;
        }

        this.isLoading = true;
        
        try {
            const result = await getCurrentWeatherAndSave({ city: this.cityName.trim() });
            
            if (result.success) {
                this.currentWeather = result.weatherData;
                this.showCurrentWeather = true;
                this.showToast('Success', result.message, 'success');
                
                // Refresh the reports
                this.refreshReports();
            } else {
                this.showToast('Error', result.message, 'error');
            }
        } catch (error) {
            this.showToast('Error', 'Failed to get weather data: ' + error.body.message, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // Delete a weather report
    async handleDeleteReport(event) {
        const reportId = event.target.dataset.id;
        
        try {
            const result = await deleteWeatherReport({ reportId: reportId });
            
            if (result.success) {
                this.showToast('Success', result.message, 'success');
                this.refreshReports();
            } else {
                this.showToast('Error', result.message, 'error');
            }
        } catch (error) {
            this.showToast('Error', 'Failed to delete report: ' + error.body.message, 'error');
        }
    }

    // Refresh all reports
    refreshReports() {
        return Promise.all([
            refreshApex(this.wiredRecentReports),
            refreshApex(this.wiredCityReports)
        ]);
    }

    // Show toast message
    showToast(title, message, variant) {
        const evt = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant,
        });
        this.dispatchEvent(evt);
    }

    // Getters for template
    get hasCurrentWeather() {
        return this.showCurrentWeather && this.currentWeather;
    }

    get hasWeatherReports() {
        return this.showReports && this.weatherReports && this.weatherReports.length > 0;
    }

    get hasRecentReports() {
        return this.recentReports && this.recentReports.length > 0;
    }

    get isGetWeatherDisabled() {
        return this.isLoading || !this.cityName.trim();
    }

    // Columns for the recent reports datatable
    get columns() {
        return [
            { label: 'City', fieldName: 'city', type: 'text' },
            { label: 'Temperature', fieldName: 'temperatureFormatted', type: 'text' },
            { label: 'Description', fieldName: 'description', type: 'text' },
            { label: 'Humidity', fieldName: 'humidityFormatted', type: 'text' },
            { label: 'Report Date', fieldName: 'reportDateTimeFormatted', type: 'text' }
        ];
    }
}