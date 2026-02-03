@isTest
private class {{ServiceTest}} {
    @isTest
    static void {{methodName}}_happyPath() {
        fflib_ApexMocks mocks = new fflib_ApexMocks();
        {{DependencyInterface}} dependency = ({{DependencyInterface}}) mocks.mock({{DependencyInterface}}.class);

        mocks.startStubbing();
        mocks.when(dependency.{{dependencyMethod}}({{dependencyArgs}})).thenReturn({{dependencyReturn}});
        mocks.stopStubbing();

        Application.Service.setMock({{DependencyInterface}}.class, dependency);

        {{ServiceInterface}} service = ({{ServiceInterface}}) Application.Service.newInstance({{ServiceInterface}}.class);

        Test.startTest();
        {{ReturnType}} result = service.{{methodName}}({{methodArgs}});
        Test.stopTest();

        System.assertEquals({{expected}}, result);
        (({{DependencyInterface}}) mocks.verify(dependency, 1)).{{dependencyMethod}}({{dependencyArgs}});
    }
}
