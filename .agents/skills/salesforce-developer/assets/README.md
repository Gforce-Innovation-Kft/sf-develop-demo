# assets/ — GForce fflib templates

Read the file matching the layer you are about to write, then adapt it. These exist so generated
code follows the GForce shape rather than the generic shape `platform-apex-generate` would
otherwise produce.

| File                      | Layer             | The thing it exists to demonstrate                                                |
| ------------------------- | ----------------- | --------------------------------------------------------------------------------- |
| `AccountsSelector.cls`    | Selector          | the `DataAccess.USER_MODE` constructor — **fflib enforces nothing without it**    |
| `IAccountsService.cls`    | Service interface | the mock seam that makes the service testable                                     |
| `AccountsServiceImpl.cls` | Service           | guard clause, query before the loop, one `commitWork()`, `Logger.*`               |
| `Accounts.cls`            | Domain            | `onApplyDefaults` / `onValidate`, `addError` on the record not a thrown exception |
| `AccountsServiceTest.cls` | Test              | positive + 200-record bulk + negative, asserting **one** commit                   |

## Registration

None of this works until the classes are registered in `Application.cls`:

```apex
public static final fflib_Application.ServiceFactory Service =
    new fflib_Application.ServiceFactory(new Map<Type, Type>{
        IAccountsService.class => AccountsServiceImpl.class
    });

public static final fflib_Application.SelectorFactory Selector =
    new fflib_Application.SelectorFactory(new Map<SObjectType, Type>{
        Account.SObjectType => AccountsSelector.class
    });

public static final fflib_Application.DomainFactory Domain =
    new fflib_Application.DomainFactory(Application.Selector, new Map<SObjectType, Type>{
        Account.SObjectType => Accounts.Constructor.class
    });

public static final fflib_Application.UnitOfWorkFactory UnitOfWork =
    new fflib_Application.UnitOfWorkFactory(new List<SObjectType>{ Account.SObjectType });
```

Forgetting this is the single most common cause of "the mock isn't being used" in tests.

## Notes

- Standard `Account` fields only, so these compile in any org without custom metadata.
- No `*-meta.xml` here — these are reference material, not deployable metadata. To compile-check
  them, copy into a package directory and deploy to a scratch org.
- API version: take it from the target repo's `sfdx-project.json` → `sourceApiVersion`. Do not
  hardcode one.
