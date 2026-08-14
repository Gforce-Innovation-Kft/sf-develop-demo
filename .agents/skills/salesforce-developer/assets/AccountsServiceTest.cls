/**
 * TEMPLATE — Test class.
 *
 * Demonstrates the three tests every public service method needs:
 *   1. positive  — it does the thing
 *   2. bulk      — it survives 200 records (the trigger batch size)
 *   3. negative  — it handles null/empty/bad input without blowing up
 *
 * Unit tests mock the Selector and Unit of Work through the Application factory, so they run
 * with zero DML and zero SOQL. That is what makes them fast enough to run on every commit.
 */
@IsTest
private class AccountsServiceTest {
  @IsTest
  static void reassignsOwnerForEveryRequestedAccount() {
    fflib_ApexMocks mocks = new fflib_ApexMocks();
    fflib_ISObjectUnitOfWork uowMock = new fflib_SObjectMocks.SObjectUnitOfWork(
      mocks
    );
    AccountsSelector selectorMock = (AccountsSelector) mocks.mock(
      AccountsSelector.class
    );

    Id ownerId = UserInfo.getUserId();
    Account acc = new Account(
      Id = fflib_IDGenerator.generate(Account.SObjectType),
      Name = 'Acme'
    );

    mocks.startStubbing();
    mocks.when(selectorMock.sObjectType()).thenReturn(Account.SObjectType);
    mocks.when(selectorMock.selectById(new Set<Id>{ acc.Id }))
      .thenReturn(new List<Account>{ acc });
    mocks.stopStubbing();

    Application.UnitOfWork.setMock(uowMock);
    Application.Selector.setMock(selectorMock);

    Test.startTest();
    new AccountsServiceImpl().reassignOwner(new Set<Id>{ acc.Id }, ownerId);
    Test.stopTest();

    // Assert the interaction, not just the absence of an exception.
    ((fflib_ISObjectUnitOfWork) mocks.verify(uowMock, 1))
      .registerDirty(
        fflib_Match.sObjectWith(
          new Map<SObjectField, Object>{ Account.OwnerId => ownerId }
        )
      );
    ((fflib_ISObjectUnitOfWork) mocks.verify(uowMock, 1)).commitWork();
  }

  @IsTest
  static void handlesFullTriggerBatch() {
    fflib_ApexMocks mocks = new fflib_ApexMocks();
    fflib_ISObjectUnitOfWork uowMock = new fflib_SObjectMocks.SObjectUnitOfWork(
      mocks
    );
    AccountsSelector selectorMock = (AccountsSelector) mocks.mock(
      AccountsSelector.class
    );

    List<Account> accounts = new List<Account>();
    Set<Id> ids = new Set<Id>();
    for (Integer i = 0; i < 200; i++) {
      Id accId = fflib_IDGenerator.generate(Account.SObjectType);
      accounts.add(new Account(Id = accId, Name = 'Acme ' + i));
      ids.add(accId);
    }

    mocks.startStubbing();
    mocks.when(selectorMock.sObjectType()).thenReturn(Account.SObjectType);
    mocks.when(selectorMock.selectById(ids)).thenReturn(accounts);
    mocks.stopStubbing();

    Application.UnitOfWork.setMock(uowMock);
    Application.Selector.setMock(selectorMock);

    Test.startTest();
    new AccountsServiceImpl().reassignOwner(ids, UserInfo.getUserId());
    Test.stopTest();

    // 200 records registered, but still exactly ONE commit. This is the assertion that
    // actually proves bulkification.
    ((fflib_ISObjectUnitOfWork) mocks.verify(uowMock, 200))
      .registerDirty((SObject) fflib_Match.anySObject());
    ((fflib_ISObjectUnitOfWork) mocks.verify(uowMock, 1)).commitWork();
  }

  @IsTest
  static void doesNothingForEmptyOrNullInput() {
    fflib_ApexMocks mocks = new fflib_ApexMocks();
    fflib_ISObjectUnitOfWork uowMock = new fflib_SObjectMocks.SObjectUnitOfWork(
      mocks
    );
    Application.UnitOfWork.setMock(uowMock);

    Test.startTest();
    new AccountsServiceImpl().reassignOwner(null, UserInfo.getUserId());
    new AccountsServiceImpl()
      .reassignOwner(new Set<Id>(), UserInfo.getUserId());
    new AccountsServiceImpl()
      .reassignOwner(
        new Set<Id>{ fflib_IDGenerator.generate(Account.SObjectType) },
        null
      );
    Test.stopTest();

    ((fflib_ISObjectUnitOfWork) mocks.verify(uowMock, 0)).commitWork();
  }
}
