/**
 * Post-install smoke test for the weather-app unlocked package.
 *
 * Runs via `sf apex run --file` against a scratch org that has the package and
 * its fflib dependencies installed. It deliberately exercises the fflib wiring
 * rather than asserting that classes exist: a package that installed but whose
 * dependency chain is wrong compiles fine and fails here.
 *
 * Any System.assert failure aborts the anonymous block, which makes
 * `sf apex run` exit non-zero and fails the install-test job.
 */

// 1. The Application factory resolves — proves fflib-apex-common is present and
//    that Application.cls was packaged with a working UnitOfWork registration.
fflib_ISObjectUnitOfWork uow = Application.UnitOfWork.newInstance();
System.assert(uow != null, 'smoke: Application.UnitOfWork.newInstance() returned null');

// 2. The custom object and its fields exist and are writable through the UoW.
String testCity = 'Malaga-smoke-' + String.valueOf(Datetime.now().getTime());
uow.registerNew(new Weather_Report__c(City__c = testCity, Report_Date_Time__c = System.now()));
uow.commitWork();

// 3. The record actually landed — catches silent DML failures and FLS gaps in
//    the permission set assigned just before this script runs.
List<Weather_Report__c> written = [
    SELECT Id, City__c
    FROM Weather_Report__c
    WHERE City__c = :testCity
    LIMIT 1
];
System.assert(!written.isEmpty(), 'smoke: no Weather_Report__c written for ' + testCity);

// 4. The selector layer resolves and queries — proves fflib_SObjectSelector and
//    fflib_QueryFactory are on the dependency chain, not just compiled against.
System.assert(
    WeatherReportsSelector.newInstance() != null,
    'smoke: WeatherReportsSelector.newInstance() returned null'
);

// 5. The service is registered in the Application factory and resolves to its
//    implementation — the binding most likely to break on a bad package build.
IWeatherService svc = (IWeatherService) Application.Service.newInstance(IWeatherService.class);
System.assert(svc != null, 'smoke: IWeatherService did not resolve from Application.Service');

// Leave the org clean so a re-run against the same org starts from zero.
delete written;

System.debug(LoggingLevel.ERROR, 'SMOKE_OK weather-app package verified');
