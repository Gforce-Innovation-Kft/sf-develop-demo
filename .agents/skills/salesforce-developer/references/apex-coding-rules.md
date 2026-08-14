# GForce Apex Coding Rules

Read this file before generating any Apex code. These rules are non-negotiable on all GForce engagements.

---

## 1. Bulkification

All Apex must handle 200+ records without hitting governor limits.

**BAD**

```apex
for (Account acc : accounts) {
    Contact c = [SELECT Id FROM Contact WHERE AccountId = :acc.Id LIMIT 1]; // SOQL in loop
    update c;  // DML in loop
}
```

**GOOD**

```apex
Set<Id> accountIds = new Map<Id, Account>(accounts).keySet();
Map<Id, Contact> contactsByAccount = new Map<Id, Contact>();
for (Contact c : [SELECT Id, AccountId FROM Contact WHERE AccountId IN :accountIds WITH USER_MODE]) {
    contactsByAccount.put(c.AccountId, c);
}
fflib_ISObjectUnitOfWork uow = Application.UnitOfWork.newInstance();
for (Account acc : accounts) {
    if (contactsByAccount.containsKey(acc.Id)) {
        Contact c = contactsByAccount.get(acc.Id);
        c.Description = 'Updated';
        uow.registerDirty(c);
    }
}
uow.commitWork();
```

Rules:

- Never place SOQL inside any loop (`for`, `while`, `do-while`)
- Never place DML inside any loop — always use Unit of Work
- Use `Map<Id, SObject>` for O(1) lookups instead of nested loops
- Pre-aggregate with Maps/Sets before processing collections
- Batch operations: always process collections, never single records

---

## 2. Architecture — Layer Delegation

```
Trigger → TriggerHandler → Domain → Selector (SOQL) → Service → UnitOfWork (DML) → Gateway (HTTP)
```

### Trigger (zero logic)

```apex
trigger AccountTrigger on Account(
  before insert,
  before update,
  after insert,
  after update
) {
  AccountTriggerHandler.run();
}
```

### TriggerHandler (delegation only)

Lives in `force-app/main/default/classes/triggerhandlers/`. Delegates to the
domain via its `Constructor` inner class — fflib instantiates the domain through
the `IConstructable` constructor, not the domain type directly.

```apex
public with sharing class AccountTriggerHandler {
  public static void run() {
    fflib_SObjectDomain.triggerHandler(AccountDomain.Constructor.class);
  }
}
```

### Domain (SObject-specific validation and rules)

```apex
public with sharing class AccountDomain extends fflib_SObjectDomain {
  public AccountDomain(List<Account> records) {
    super(records);
  }

  public class Constructor implements fflib_SObjectDomain.IConstructable {
    public fflib_SObjectDomain construct(List<SObject> records) {
      return new AccountDomain(records);
    }
  }

  public override void onBeforeInsert() {
    validateRequiredFields((List<Account>) Records);
  }

  private void validateRequiredFields(List<Account> accounts) {
    for (Account acc : accounts) {
      if (String.isBlank(acc.Name)) {
        acc.addError('Account Name is required.');
      }
    }
  }
}
```

### Selector (SOQL only — no DML, no business logic)

```apex
public with sharing class AccountSelector extends fflib_SObjectSelector implements IAccountSelector {
  public List<Schema.SObjectField> getSObjectFieldList() {
    return new List<Schema.SObjectField>{
      Account.Id,
      Account.Name,
      Account.Industry
    };
  }
  public Schema.SObjectType getSObjectType() {
    return Account.SObjectType;
  }

  // REQUIRED: fflib enforces nothing by default (DataAccess.LEGACY).
  // Pass DataAccess.USER_MODE so queries emit WITH USER_MODE.
  public AccountsSelector() {
    super(false, true, true, true, DataAccess.USER_MODE);
  }

  public List<Account> selectById(Set<Id> ids) {
    return (List<Account>) selectSObjectsById(ids);
  }

  public List<Account> selectByIndustry(String industry) {
    fflib_QueryFactory qf = newQueryFactory();
    qf.setCondition('Industry = :industry');
    return (List<Account>) Database.query(qf.toSOQL());
  }
}
```

### Service (orchestration — uses Domain + Selector + UoW)

```apex
public with sharing class AccountServiceImpl implements IAccountService {
  public void updateIndustry(Set<Id> accountIds, String newIndustry) {
    IAccountSelector selector = (IAccountSelector) Application.Selector.newInstance(
      Account.SObjectType
    );
    List<Account> accounts = selector.selectById(accountIds);

    fflib_ISObjectUnitOfWork uow = Application.UnitOfWork.newInstance();
    for (Account acc : accounts) {
      acc.Industry = newIndustry;
      uow.registerDirty(acc);
    }
    uow.commitWork();
    Logger.info('Updated industry for ' + accounts.size() + ' accounts')
      .addTag('AccountService');
    Logger.saveLog();
  }
}
```

---

## 3. Security

**Every SOQL query must have `WITH USER_MODE` or use `Security.stripInaccessible`.**

> **fflib does NOT enforce FLS by default.** `fflib_SObjectSelector` defaults to
> `DataAccess.LEGACY` and `fflib_QueryFactory` to `FLSEnforcement.NONE`, which emits no
> FLS clause on the query. Every selector must opt in via its constructor —
> `super(..., DataAccess.USER_MODE)`. A selector that does not silently runs with FLS
> unenforced — CRUD is still checked by default (`m_enforceCRUD = true`), and the
> `with sharing` parent class still applies. Verified against `libs/fflib-apex-common` in this repo.

```apex
// Via fflib selector (preferred) — the selector must be constructed with DataAccess.USER_MODE
List<Account> accounts = selector.selectById(ids);

// Manual SOQL — must add it explicitly
List<Account> accounts = [SELECT Id, Name FROM Account WHERE Id IN :ids WITH USER_MODE];

// For dynamic SOQL or when you need stripInaccessible
SObjectAccessDecision decision = Security.stripInaccessible(
    AccessType.READABLE,
    [SELECT Id, Name, AnnualRevenue FROM Account WHERE Id IN :ids]
);
List<Account> accounts = (List<Account>) decision.getRecords();
```

All classes use `with sharing` unless justified in a comment:

```apex
public with sharing class AccountServiceImpl implements IAccountService { ... }
// without sharing — only for specific system-context operations (e.g., platform event triggers)
public without sharing class PlatformEventHandler { ... }
```

Never hardcode record IDs, profile names, or org URLs. Use Custom Metadata, Custom Settings, or Named Credentials.

---

## 4. NebulaLogger — No System.debug

**Always use NebulaLogger. Never use System.debug in production code.**

```apex
// Informational
Logger.info('Processing ' + accounts.size() + ' accounts').addTag('AccountService');

// Warning
Logger.warn('Account has no BillingCountry: ' + acc.Id).setRecord(acc);

// Error with exception
try {
    callout();
} catch (CalloutException e) {
    Logger.error('Callout failed', e);
    Logger.saveLog();
    throw e;
}

// Always flush at natural exit points
Logger.saveLog();
```

Rules:

- Every public method entry point should log at info level with context
- Every catch block must log at error level with the exception
- `Logger.saveLog()` must be called before returning from a service method or after logging in a catch block
- Use `.setRecord(sObject)` to link log entries to records
- Use `.addTag('ClassName')` for filtering in the UI

---

## 5. Exception Handling

Use specific exception types. Never swallow exceptions silently.

```apex
// Custom exception type per domain
public class AccountServiceException extends Exception {}

// Catch and re-throw with context
try {
    uow.commitWork();
} catch (DmlException e) {
    Logger.error('DML failed in AccountService.updateIndustry', e);
    Logger.saveLog();
    throw new AccountServiceException('Failed to update accounts: ' + e.getMessage(), e);
}
```

- Use `Database.insert(records, false)` (partial save) only when intentional — log each failure
- Prefer `allOrNone = true` (default) for data integrity
- Callout exceptions must always be caught and logged before re-throwing

---

## 6. Naming Conventions

| Type               | Pattern                  | Example                  |
| ------------------ | ------------------------ | ------------------------ |
| Domain             | `{Object}Domain`         | `AccountDomain`          |
| Domain interface   | `I{Object}Domain`        | `IAccountDomain`         |
| Selector           | `{Object}Selector`       | `AccountSelector`        |
| Selector interface | `I{Object}Selector`      | `IAccountSelector`       |
| Service impl       | `{Object}ServiceImpl`    | `AccountServiceImpl`     |
| Service interface  | `I{Object}Service`       | `IAccountService`        |
| Trigger handler    | `{Object}TriggerHandler` | `AccountTriggerHandler`  |
| Trigger            | `{Object}Trigger`        | `AccountTrigger`         |
| Gateway            | `{Name}Gateway`          | `ExternalCrmGateway`     |
| DTO                | `{Object}DTO`            | `AccountDTO`             |
| Test factory       | `{Object}TestFactory`    | `AccountTestFactory`     |
| Test class         | `{Subject}Test`          | `AccountServiceImplTest` |

- Method names: verb-first, describe intent (`updateIndustry`, `selectByStatus`, `validateAddress`)
- Variables: camelCase, descriptive (`accountsByIndustry`, not `map1`)
- Constants: SCREAMING_SNAKE_CASE in a `Constants` class or Custom Metadata
- No abbreviations: `numberOfRecords` not `numRecs`, `accountIdentifier` not `acctId`

---

## 7. Async Apex

Prefer `Queueable` over `@future`. Use `Batch` for data processing > 10k records.

```apex
// Queueable (preferred)
public class AccountSyncQueueable implements Queueable, Database.AllowsCallouts {
    private final Set<Id> accountIds;
    public AccountSyncQueueable(Set<Id> accountIds) { this.accountIds = accountIds; }
    public void execute(QueueableContext ctx) {
        IAccountService svc = (IAccountService) Application.Service.newInstance(IAccountService.class);
        svc.syncToExternalSystem(accountIds);
    }
}
System.enqueueJob(new AccountSyncQueueable(ids));

// @future — only when Queueable is not available (e.g., from a Batch finish method)
@future(callout=true)
public static void syncAccountFuture(Set<Id> accountIds) { ... }
```

- Never chain Queueables beyond 5 levels without a guard
- Batch `execute()` must be bulkified — it receives up to 2000 records per chunk

---

## 8. Governor Limit Awareness

| Limit          | Safe threshold | Action if approaching                        |
| -------------- | -------------- | -------------------------------------------- |
| SOQL queries   | 50             | Consolidate selectors, use caching           |
| DML statements | 75             | All DML through UoW (1 commit = 1 statement) |
| SOQL rows      | 25,000         | Add LIMIT, paginate, use Batch               |
| Heap size      | 6 MB           | Process records in chunks, avoid large Lists |
| CPU time       | 8,000 ms       | Move computation to async                    |
| Callouts       | 100            | Batch callouts in Queueable                  |

Always use `Limits.getQueries()` guards in Batch `execute()` if dynamically issuing SOQL.

---

## 9. API Version

**Never hardcode an API version. Read it from the repo you are working in** —
`sfdx-project.json` → `sourceApiVersion` — and put that value in every new `*-meta.xml`.

Consuming repos differ — check the current repo's value rather than assuming one. The official
`platform-apex-generate` skill defaults to **66.0** and will use that unless told otherwise, so
state the repo's version explicitly when invoking it.

Match the files around you. A new class on a different API version than its neighbours is a
review comment, not a feature.

Use `AccessLevel.USER_MODE` for DML when targeting API 56+:

```apex
Database.insert(records, AccessLevel.USER_MODE);
```

---

## 10. Anti-Patterns (never do these)

- `[SELECT * FROM ...]` — enumerate fields explicitly
- `SeeAllData=true` in tests — use TestDataFactory
- Logic in triggers — zero tolerance
- `System.debug` — use NebulaLogger
- Hardcoded IDs (e.g., `'0015g00000...'`) — use Custom Metadata or query
- SOQL/DML in loops — zero tolerance
- `without sharing` without a comment explaining why
- Static variables used as cross-request caches (they reset per transaction)
- `@future` when Queueable is possible
- Catch `Exception e` without re-throwing or logging
