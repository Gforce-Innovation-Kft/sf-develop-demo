# GForce Testing — TestDataFactory (benahm) Reference

Source-tracked in `force-app/main/default/classes/TestDataFactory.cls`.  
Read this file when writing any `@isTest` class. Always use TestDataFactory — never `new Account(Name='test')` directly.

---

## Core API

```apex
// Single record — auto-inserts, all required fields auto-filled
Account acc = (Account) TestDataFactory.createSObject('Account');

// Single record — no insert
Account acc = (Account) TestDataFactory.createSObject('Account', false);

// Single record with field overrides — auto-inserts
Account acc = (Account) TestDataFactory.createSObject('Account', new Map<String,Object>{
    'Name'        => 'Acme Corp',
    'Industry'    => 'Technology',
    'BillingCity' => 'Madrid'
});

// Single record with overrides, no insert
Account acc = (Account) TestDataFactory.createSObject('Account', new Map<String,Object>{
    'Name' => 'Acme Corp'
}, false);

// Bulk — 200 records, auto-inserted
List<Account> accs = TestDataFactory.createSObjectList('Account', 200);

// Bulk with overrides
List<Contact> cons = TestDataFactory.createSObjectList('Contact', new Map<String,Object>{
    'LastName' => 'Smith'
}, 50);

// Bulk with cycling values (index wraps)
List<Contact> cons = TestDataFactory.createSObjectList('Contact', new Map<String,Object>{
    'LastName' => new List<String>{ 'Smith', 'Jones', 'Brown' }
}, 9, false); // produces Smith,Jones,Brown,Smith,Jones,Brown,Smith,Jones,Brown
```

---

## Auto-generated field name pattern

When no override is given, text fields default to `'test{index}'` (0-based):

```
Record 0 → Name = 'test0'
Record 1 → Name = 'test1'
```

Use `{!index}` merge syntax in string overrides to get per-record uniqueness:

```apex
TestDataFactory.createSObjectList('Account', new Map<String,Object>{
    'Owner.Username'          => 'qa{!index}@acme.developer',
    'Owner.CommunityNickname' => 'qa{!index}',
    'Owner.ProfileId'         => UserInfo.getProfileId()
}, 5);
```

---

## Cross-object / relationship overrides

Dot-notation resolves relationships and auto-inserts parents before children:

```apex
// Flat dot-notation (auto-creates and inserts Contact + Account parents)
Case cse = (Case) TestDataFactory.createSObject('Case', new Map<String,Object>{
    'Contact.FirstName'       => 'Maria',
    'Contact.Account.Name'    => 'Acme Corp'
}, false);

// Nested map syntax — same result, more readable for deep trees
Case cse = (Case) TestDataFactory.createSObject('Case', new Map<String,Object>{
    'Contact' => new Map<String,Object>{
        'FirstName' => 'Maria',
        'Account'   => new Map<String,Object>{
            'Name'        => 'Acme Corp',
            'BillingCity' => 'London'
        }
    }
}, false);

// Pass an already-inserted SObject as a relationship value
Account acc = (Account) TestDataFactory.createSObject('Account');
Case cse = (Case) TestDataFactory.createSObject('Case', new Map<String,Object>{
    'Contact' => new Map<String,Object>{
        'Account' => acc  // uses acc.Id — no re-insert
    }
}, false);

// List of parents mapped per-index to children
List<Account> accs = TestDataFactory.createSObjectList('Account', 3);
List<Contact> cons = TestDataFactory.createSObjectList('Contact', new Map<String,Object>{
    'Account' => accs  // cons[0].AccountId = accs[0].Id, etc.
}, 3);
```

> ⚠️ **Do not link a custom lookup with `__r.Name` dot-notation on an inserted
> record.** Writing `'Account__r.Name' => 'Test Account'` makes the platform treat
> `Account__r` as an external foreign-key reference, which fails on insert:
> `Cannot specify both an external ID reference Account__r and a salesforce id, Account__c`
> and `More than 1 field provided in an external foreign key reference`.
>
> Instead create the real parent via its own factory and set the `__c` Id (or pass
> the inserted SObject as the relationship value). See the `withAccount` pattern below.

---

## DEFAULT_VALUE sentinel

Force auto-generation on a specific field even when you're overriding others:

```apex
TestDataFactory.createSObject('Case', new Map<String,Object>{
    'Subject'     => 'My subject',
    'Description' => TestDataFactory.DEFAULT_VALUE  // auto-generated
});
```

---

## GForce project-specific factory wrappers

For each SObject, create a project-level wrapper in `force-app/main/default/classes/tests/factories/`:

```apex
// AccountTestFactory.cls
@IsTest
public class AccountTestFactory {
  public static Account createAccount(Map<String, Object> overrides) {
    Map<String, Object> defaults = new Map<String, Object>{
      'Name' => 'Test Account',
      'Industry' => 'Technology'
    };
    if (overrides != null)
      defaults.putAll(overrides);
    return (Account) TestDataFactory.createSObject('Account', defaults);
  }

  public static List<Account> createAccounts(
    Integer count,
    Map<String, Object> overrides
  ) {
    Map<String, Object> defaults = new Map<String, Object>{
      'Name' => 'Test Account {!index}',
      'Industry' => 'Technology'
    };
    if (overrides != null)
      defaults.putAll(overrides);
    return TestDataFactory.createSObjectList('Account', defaults, count);
  }
}
```

Usage in tests:

```apex
Account acc = AccountTestFactory.createAccount(new Map<String,Object>{ 'Name' => 'Acme' });
List<Account> accs = AccountTestFactory.createAccounts(200, null);
```

### Child factory with a real parent (the `withAccount` pattern)

When a record needs a parent via a **custom lookup**, the wrapper creates the
parent through its own factory and sets the `__c` Id — only on the insert path,
so `doInsert = false` builds stay DML-free. This is the correct alternative to
`__r.Name` dot-notation (see the warning above).

```apex
// InvoiceTestFactory.cls
public static Invoice__c createInvoice(Map<String, Object> overrides, Boolean doInsert) {
  Map<String, Object> defaults = withAccount(overrides, doInsert);
  if (overrides != null) {
    defaults.putAll(overrides);
  }
  return (Invoice__c) TestDataFactory.createSObject('Invoice__c', defaults, doInsert);
}

private static Map<String, Object> withAccount(Map<String, Object> overrides, Boolean doInsert) {
  Map<String, Object> defaults = new Map<String, Object>{
    'Amount__c' => 100,
    'Currency_ISO__c' => 'USD'
  };
  Boolean callerSuppliedAccount = overrides != null && overrides.containsKey('Account__c');
  if (doInsert && !callerSuppliedAccount) {
    Account parent = AccountTestFactory.createAccount(null); // inserted, has an Id
    defaults.put('Account__c', parent.Id);
  }
  return defaults;
}
```

For pure fflib unit tests that mock selectors/UoW and must not touch the DB, expose
a separate in-memory builder that assigns fake Ids and sets no relationships:

```apex
public static List<Invoice__c> createInvoicesInMemory(Integer count, String currencyIso) {
  List<Invoice__c> invoices = new List<Invoice__c>();
  for (Integer i = 0; i < count; i++) {
    invoices.add(new Invoice__c(
      Id = fflib_IDGenerator.generate(Invoice__c.SObjectType),
      Amount__c = 100,
      Currency_ISO__c = currencyIso,
      Status__c = 'Draft'
    ));
  }
  return invoices;
}
```

---

## Custom DefaultValueProvider (advanced)

Extend `TestDataFactory.DefaultValueProvider` to force required or optional fields for your org:

```apex
@IsTest
public class GForceDefaultValueProvider extends TestDataFactory.DefaultValueProvider {
  public override Set<String> defineSObjectRequiredFields(
    Schema.SObjectType t
  ) {
    if (t == Opportunity.SObjectType) {
      return new Set<String>{ 'StageName', 'CloseDate', 'Pricebook2Id' };
    }
    return null;
  }

  public override Set<String> defineSObjectOptionalFields(
    Schema.SObjectType t
  ) {
    if (t == Contact.SObjectType) {
      return new Set<String>{ 'ReportsToId' }; // skip this optional required field
    }
    return null;
  }
}
```

Set it once in a `@TestSetup` method or test class static block:

```apex
@TestSetup
static void setup() {
    TestDataFactory.defaultValueProvider = new GForceDefaultValueProvider();
}
```

---

## Standard test class pattern (GForce)

```apex
@IsTest
private class AccountServiceImplTest {
  @TestSetup
  static void makeData() {
    // Insert shared data once — all test methods share it via SOQL
    AccountTestFactory.createAccounts(5, null);
  }

  @IsTest
  static void testPositive_processAccounts() {
    List<Account> accs = [SELECT Id, Name FROM Account];

    Test.startTest();
    AccountServiceImpl.processAccounts(accs);
    Test.stopTest();

    // Assert expected outcome
    List<Account> result = [
      SELECT Id, Status__c
      FROM Account
      WHERE Status__c = 'Processed'
    ];
    System.assertEquals(5, result.size(), 'All accounts should be processed');
  }

  @IsTest
  static void testNegative_emptyInput() {
    Test.startTest();
    try {
      AccountServiceImpl.processAccounts(new List<Account>());
      System.assert(false, 'Expected exception');
    } catch (AccountServiceImpl.AccountServiceException e) {
      System.assert(e.getMessage().contains('No accounts'), e.getMessage());
    }
    Test.stopTest();
  }

  @IsTest
  static void testBulk_200Records() {
    List<Account> accs = [SELECT Id FROM Account]; // 5 from makeData
    List<Account> extra = AccountTestFactory.createAccounts(195, null);
    accs.addAll(extra);

    Test.startTest();
    AccountServiceImpl.processAccounts(accs);
    Test.stopTest();

    System.assertEquals(
      200,
      [SELECT COUNT() FROM Account WHERE Status__c = 'Processed']
    );
  }
}
```

---

## Rules

- Always `@isTest` + `@TestSetup` — never `SeeAllData=true`
- Use `AccountTestFactory` (wrapper) in tests, not `TestDataFactory` directly — keeps field defaults in one place
- Bulk test = 200 records minimum (governor limit boundary)
- `Test.startTest()` / `Test.stopTest()` isolates governor limit context
- Assert on specific field values, not just `assertNotEquals(null, ...)`
- Test class name: `{ClassName}Test` (e.g., `AccountServiceImplTest`)
