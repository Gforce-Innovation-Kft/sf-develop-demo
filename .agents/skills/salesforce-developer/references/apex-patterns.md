# GForce Apex Patterns — fflib Enterprise Architecture

Read this file when generating any fflib-pattern Apex class (domain, selector, service, UoW, application factory, mocks).

---

## Application Factory (`Application.cls`)

Central registry for all layers. Every new SObject's classes must be registered here.

```apex
public class Application {
  public static final fflib_Application.ServiceFactory Service = new fflib_Application.ServiceFactory(
    new Map<Type, Type>{ IAccountService.class => AccountServiceImpl.class }
  );

  public static final fflib_Application.SelectorFactory Selector = new fflib_Application.SelectorFactory(
    new Map<SObjectType, Type>{ Account.SObjectType => AccountSelector.class }
  );

  public static final fflib_Application.DomainFactory Domain = new fflib_Application.DomainFactory(
    Application.Selector,
    new Map<SObjectType, Type>{
      Account.SObjectType => AccountDomain.Constructor.class
    }
  );

  public static final fflib_Application.UnitOfWorkFactory UnitOfWork = new fflib_Application.UnitOfWorkFactory(
    new List<SObjectType>{
      Account.SObjectType,
      Contact.SObjectType
      // Order matters for DML: parent before child
    }
  );
}
```

**Adding a new SObject:** register in all four maps (Service, Selector, Domain, UoW).

---

## Domain Layer

Handles trigger logic, field validation, and SObject-specific rules. No SOQL. No DML.

```apex
public with sharing class AccountDomain extends fflib_SObjectDomain implements IAccountDomain {
  public AccountDomain(List<Account> records) {
    super(records);
  }

  // Required inner class for fflib factory
  public class Constructor implements fflib_SObjectDomain.IConstructable {
    public fflib_SObjectDomain construct(List<SObject> records) {
      return new AccountDomain(records);
    }
  }

  // Trigger lifecycle hooks — override only what you need
  public override void onBeforeInsert() {
    validateRequiredFields((List<Account>) Records);
  }

  public override void onBeforeUpdate(Map<Id, SObject> existingRecords) {
    Map<Id, Account> oldAccounts = (Map<Id, Account>) existingRecords;
    checkStatusTransition((List<Account>) Records, oldAccounts);
  }

  public override void onAfterInsert() {
    Logger.info('AccountDomain.onAfterInsert: ' + Records.size() + ' records')
      .addTag('AccountDomain');
    Logger.saveLog();
  }

  // Domain methods callable from Service layer
  public void applyDefaultRating(List<Account> accounts) {
    for (Account acc : accounts) {
      if (acc.Rating == null) {
        acc.Rating = 'Warm';
      }
    }
  }

  private void validateRequiredFields(List<Account> accounts) {
    for (Account acc : accounts) {
      if (String.isBlank(acc.Name)) {
        acc.addError('Account Name is required.');
      }
    }
  }

  private void checkStatusTransition(
    List<Account> accounts,
    Map<Id, Account> oldMap
  ) {
    for (Account acc : accounts) {
      Account old = oldMap.get(acc.Id);
      if (acc.Rating == 'Hot' && old.Rating == 'Cold') {
        acc.addError('Cannot move directly from Cold to Hot.');
      }
    }
  }
}
```

---

## Selector Layer

All SOQL lives here. No business logic. No DML. Returns typed lists/maps.

```apex
public with sharing class AccountSelector extends fflib_SObjectSelector implements IAccountSelector {
  // Required: list of fields always included in queries
  public List<Schema.SObjectField> getSObjectFieldList() {
    return new List<Schema.SObjectField>{
      Account.Id,
      Account.Name,
      Account.Industry,
      Account.Rating,
      Account.BillingCountry,
      Account.OwnerId
    };
  }

  public Schema.SObjectType getSObjectType() {
    return Account.SObjectType;
  }

  // REQUIRED: fflib defaults to DataAccess.LEGACY, which emits no security clause.
  // This constructor is what makes every query in this selector run WITH USER_MODE.
  public AccountsSelector() {
    super(false, true, true, true, DataAccess.USER_MODE);
  }

  public List<Account> selectById(Set<Id> ids) {
    return (List<Account>) selectSObjectsById(ids);
  }

  // newQueryFactory() inherits the selector's DataAccess setting — no per-query flag needed
  public List<Account> selectByIndustry(String industry) {
    fflib_QueryFactory qf = newQueryFactory();
    qf.setCondition('Industry = :industry');
    qf.addOrdering(Account.Name, fflib_QueryFactory.SortOrder.ASCENDING);
    return (List<Account>) Database.query(qf.toSOQL());
  }

  // Return a Map for O(1) lookup
  public Map<Id, Account> selectMapByIds(Set<Id> ids) {
    return new Map<Id, Account>(selectById(ids));
  }

  // Include related records with sub-selects
  public List<Account> selectWithContacts(Set<Id> ids) {
    fflib_QueryFactory qf = newQueryFactory();
    qf.setCondition('Id IN :ids');
    fflib_QueryFactory contactQf = qf.subselectQuery('Contacts');
    contactQf.selectField('Id');
    contactQf.selectField('FirstName');
    contactQf.selectField('LastName');
    return (List<Account>) Database.query(qf.toSOQL());
  }
}
```

---

## Service Layer

Orchestrates business logic. Uses Domain + Selector + UoW. One method = one business operation.

```apex
public with sharing class AccountServiceImpl implements IAccountService {
  public void updateIndustry(Set<Id> accountIds, String newIndustry) {
    Logger.info(
        'AccountServiceImpl.updateIndustry called for ' +
          accountIds.size() +
          ' accounts'
      )
      .addTag('AccountService');

    IAccountSelector selector = (IAccountSelector) Application.Selector.newInstance(
      Account.SObjectType
    );
    List<Account> accounts = selector.selectById(accountIds);

    IAccountDomain domain = (IAccountDomain) Application.Domain.newInstance(
      accounts
    );
    domain.applyDefaultRating(accounts);

    fflib_ISObjectUnitOfWork uow = Application.UnitOfWork.newInstance();
    for (Account acc : accounts) {
      acc.Industry = newIndustry;
      uow.registerDirty(acc);
    }

    try {
      uow.commitWork();
      Logger.info('Industry updated successfully').addTag('AccountService');
    } catch (DmlException e) {
      Logger.error('DML failed in updateIndustry', e);
      Logger.saveLog();
      throw new AccountServiceException(
        'Failed to update accounts: ' + e.getMessage(),
        e
      );
    }
    Logger.saveLog();
  }

  public class AccountServiceException extends Exception {
  }
}
```

---

## Unit of Work Patterns

```apex
fflib_ISObjectUnitOfWork uow = Application.UnitOfWork.newInstance();

// Register new record (INSERT)
Account newAcc = new Account(Name = 'Acme');
uow.registerNew(newAcc);

// Register new with relationship (INSERT child, relate to parent)
Contact c = new Contact(FirstName = 'Jane');
uow.registerNew(c, Contact.AccountId, newAcc);  // resolves ID before DML

// Register dirty (UPDATE)
uow.registerDirty(existingAccount);

// Register dirty with specific fields only
uow.registerDirty(existingAccount, new List<SObjectField>{ Account.Industry, Account.Rating });

// Register deleted (DELETE)
uow.registerDeleted(oldAccount);

// Commit all (single DML statement per SObject type)
uow.commitWork();
```

---

## Application Factory — Calling Instances

```apex
// Service
IAccountService svc = (IAccountService) Application.Service.newInstance(IAccountService.class);

// Selector
IAccountSelector sel = (IAccountSelector) Application.Selector.newInstance(Account.SObjectType);

// Domain (from a list of records)
IAccountDomain dom = (IAccountDomain) Application.Domain.newInstance(accounts);

// UoW
fflib_ISObjectUnitOfWork uow = Application.UnitOfWork.newInstance();
```

---

## Interfaces — always top-level classes

Every layer interface (`IAccountService`, `IAccountSelector`, `IAccountDomain`,
gateway interfaces) **must be its own top-level class file**. Do **not** nest
them as inner interfaces of their implementation.

Reason: `fflib_ApexMocks.mock()` builds mocks via the platform `Test.createStub()`
API, and `Test.createStub()` **cannot stub inner Apex classes/interfaces**.
Nesting a mocked interface produces, at test runtime:

```
System.TypeException: Test.createStub() cannot be called with inner Apex classes
```

So the standalone interface file is a hard requirement of the architecture, not a
style choice. Register the top-level interface against its impl in `Application.cls`
(`IAccountService.class => AccountServiceImpl.class`); consumers depend only on the
interface, never the impl.

---

## Mock Pattern for Tests (fflib_ApexMocks)

```apex
@isTest
private class AccountServiceImplTest {
  @TestSetup
  static void setup() {
    List<Account> accounts = AccountTestFactory.createAccounts(5);
    insert accounts;
  }

  @isTest
  static void updateIndustry_updatesAllRecords() {
    // Arrange
    fflib_ApexMocks mocks = new fflib_ApexMocks();
    IAccountSelector selectorMock = (IAccountSelector) mocks.mock(
      IAccountSelector.class
    );
    fflib_ISObjectUnitOfWork uowMock = (fflib_ISObjectUnitOfWork) mocks.mock(
      fflib_ISObjectUnitOfWork.class
    );

    List<Account> testAccounts = AccountTestFactory.createAccounts(3);
    Set<Id> testIds = new Map<Id, Account>(testAccounts).keySet();

    mocks.startStubbing();
    mocks.when(selectorMock.selectById(testIds)).thenReturn(testAccounts);
    mocks.stopStubbing();

    Application.Selector.setMock(selectorMock);
    Application.UnitOfWork.setMock(uowMock);

    // Act
    Test.startTest();
    IAccountService svc = (IAccountService) Application.Service.newInstance(
      IAccountService.class
    );
    svc.updateIndustry(testIds, 'Technology');
    Test.stopTest();

    // Assert
    ((IAccountSelector) mocks.verify(selectorMock)).selectById(testIds);
    ((fflib_ISObjectUnitOfWork) mocks.verify(uowMock, mocks.times(3)))
      .registerDirty(fflib_Match.anySObject());
    ((fflib_ISObjectUnitOfWork) mocks.verify(uowMock)).commitWork();
  }
}
```

---

## TestDataFactory (benahm)

Install via: `sf package install --package 04t1n000002WsK5AAK`

API: `TestDataFactory.createSObject(String sObjectName, Map<String, Object> fieldValues)`

```apex
public class AccountTestFactory {
  public static List<Account> createAccounts(Integer count) {
    List<Account> accounts = new List<Account>();
    for (Integer i = 0; i < count; i++) {
      accounts.add(
        (Account) TestDataFactory.createSObject(
          'Account',
          new Map<String, Object>{
            'Name' => 'Test Account ' + i,
            'Industry' => 'Technology',
            'Rating' => 'Warm',
            'BillingCountry' => 'Spain'
          }
        )
      );
    }
    return accounts;
  }

  public static Account createAccount(Map<String, Object> overrides) {
    return (Account) TestDataFactory.createSObject('Account', overrides);
  }
}
```

Rules:

- Always use `AccountTestFactory` — never construct SObjects inline in test methods
- `createAccounts()` returns unsaved records — caller decides when to insert
- Provide sensible defaults; allow override map for edge cases
