# GForce SOQL Optimization Rules

---

## 1. Always Use Bind Variables

Bind variables are indexed, prevent SOQL injection, and avoid string concatenation errors.

**BAD**

```apex
String industry = 'Technology';
List<Account> accs = Database.query('SELECT Id FROM Account WHERE Industry = \'' + industry + '\'');
```

**GOOD**

```apex
String industry = 'Technology';
List<Account> accs = [SELECT Id, Name FROM Account WHERE Industry = :industry WITH USER_MODE];
```

---

## 2. Select Only Fields You Need

Never use `SELECT *`. Enumerate fields explicitly to reduce heap usage and avoid FLS surprises.

```apex
// BAD — over-selects, hits heap limit on large results
List<Account> accs = [SELECT FIELDS(ALL) FROM Account LIMIT 200];

// GOOD — select only what the operation needs
List<Account> accs = [SELECT Id, Name, Industry, Rating FROM Account WHERE Id IN :ids WITH USER_MODE];
```

In fflib selectors, `getSObjectFieldList()` is the canonical field list for the object. Add fields there — not scattered across individual methods.

---

## 3. Selective Filters and Indexed Fields

Put the most selective filter first. Use indexed fields in WHERE clauses.

Indexed by default: `Id`, `Name`, `CreatedDate`, `LastModifiedDate`, `SystemModstamp`, `OwnerId`, `RecordTypeId`, external ID fields, fields marked as unique.

```apex
// BAD — non-indexed field first
List<Account> accs = [SELECT Id FROM Account WHERE Industry = 'Tech' AND Id IN :ids WITH USER_MODE];

// GOOD — indexed Id first
List<Account> accs = [SELECT Id FROM Account WHERE Id IN :ids AND Industry = 'Tech' WITH USER_MODE];
```

For large objects (>100k records), always filter on an indexed field to avoid full table scans.

---

## 4. LIMIT and Pagination

Always add LIMIT for non-bulk queries. Use OFFSET for pagination (max 2000).

```apex
// Single record lookup
Account acc = [SELECT Id, Name FROM Account WHERE External_Id__c = :extId WITH USER_MODE LIMIT 1];

// Paginated list
Integer pageSize = 50;
Integer offset = pageNumber * pageSize;
List<Account> page = [
    SELECT Id, Name, Industry
    FROM Account
    WHERE Industry = :industry
    WITH USER_MODE
    ORDER BY Name ASC
    LIMIT :pageSize
    OFFSET :offset
];
```

For OFFSET > 2000, use cursor-based pagination via `CreatedDate > :lastSeenDate ORDER BY CreatedDate ASC LIMIT :pageSize`.

---

## 5. Avoid Cross-Object Formulas in WHERE

Formula fields are not indexed. Filter on base fields, not formula results.

```apex
// BAD — filtering on a formula field (full scan)
List<Account> accs = [SELECT Id FROM Account WHERE Is_Enterprise__c = true WITH USER_MODE];

// GOOD — filter on the base field the formula is derived from, or use a real field
List<Account> accs = [SELECT Id FROM Account WHERE AnnualRevenue > 1000000 WITH USER_MODE];
```

If you must filter on a formula field, consider adding a real `__c` field updated by a trigger/flow.

---

## 6. fflib Selector Patterns

Use `fflib_QueryFactory` for all custom queries in selectors — it handles `WITH USER_MODE`, ordering, sub-selects, and field merging.

```apex
public List<Account> selectByRatingAndIndustry(String rating, String industry) {
    fflib_QueryFactory qf = newQueryFactory(); // includes getSObjectFieldList() automatically
    qf.setCondition('Rating = :rating AND Industry = :industry');
    qf.addOrdering(Account.Name, fflib_QueryFactory.SortOrder.ASCENDING);
    qf.setLimit(200);
    return (List<Account>) Database.query(qf.toSOQL());
}

// Sub-select (parent-child)
public List<Account> selectWithContacts(Set<Id> ids) {
    fflib_QueryFactory qf = newQueryFactory();
    qf.setCondition('Id IN :ids');
    fflib_QueryFactory contactQf = qf.subselectQuery('Contacts');
    contactQf.selectField('Id').selectField('FirstName').selectField('Email');
    return (List<Account>) Database.query(qf.toSOQL());
}
```

---

## 7. Avoid SOQL in Loops (Zero Tolerance)

Move all queries outside loops. Use `Map<Id, SObject>` for record lookup after a single query.

```apex
// BAD
for (Opportunity opp : opportunities) {
    Account acc = [SELECT Id, Name FROM Account WHERE Id = :opp.AccountId LIMIT 1]; // N+1 SOQL
}

// GOOD
Set<Id> accountIds = new Set<Id>();
for (Opportunity opp : opportunities) { accountIds.add(opp.AccountId); }

Map<Id, Account> accountMap = new Map<Id, Account>(
    [SELECT Id, Name FROM Account WHERE Id IN :accountIds WITH USER_MODE]
);
for (Opportunity opp : opportunities) {
    Account acc = accountMap.get(opp.AccountId);
}
```

---

## 8. COUNT and Aggregate Queries

Use `COUNT()` and aggregates for summary data — don't pull records just to count them.

```apex
// BAD — pulls all records just to count
Integer count = [SELECT Id FROM Account WHERE Industry = 'Tech' WITH USER_MODE].size();

// GOOD
Integer count = [SELECT COUNT() FROM Account WHERE Industry = 'Tech' WITH USER_MODE];

// Aggregates
List<AggregateResult> results = [
    SELECT Industry, COUNT(Id) total
    FROM Account
    WHERE CreatedDate = THIS_YEAR
    WITH USER_MODE
    GROUP BY Industry
    ORDER BY COUNT(Id) DESC
];
```

---

## 9. SOQL Row Limit Awareness

Default SOQL row limit: 50,000 per transaction. Batch Apex: 50,000 per `execute()` chunk.

For queries that might return large data sets:

- Add `LIMIT` to cap rows
- Use Batch Apex with `QueryLocator` for processing all records
- Use `OFFSET` pagination for UI queries

```apex
// Batch Apex — QueryLocator handles millions of records
public Database.QueryLocator start(Database.BatchableContext bc) {
    return Database.getQueryLocator([
        SELECT Id, Name, Industry FROM Account WHERE IsActive__c = true WITH USER_MODE
    ]);
}
```

---

## 10. Use `getOrderBy()` and `getAdditionalQueryClause()` in Selectors

fflib selector base class provides hooks for consistent sorting and filtering:

```apex
public override String getOrderBy() {
    return 'Name ASC';
}

public override String getAdditionalQueryClause() {
    return 'IsDeleted = false'; // appended to all queries from this selector
}
```
