/**
 * TEMPLATE — Domain layer.
 *
 * Register in Application.cls:
 *   Account.SObjectType => Accounts.Constructor.class
 *
 * The Domain owns validation and defaulting for ONE SObject. It does not query and it does not
 * commit — it operates on the records it was handed. Business logic that spans objects belongs
 * in a Service, not here.
 */
public with sharing class Accounts extends fflib_SObjectDomain {
    public Accounts(List<Account> records) {
        super(records);
    }

    /** Required by fflib so the Domain can be built from the factory. */
    public class Constructor implements fflib_SObjectDomain.IConstructable {
        public fflib_SObjectDomain construct(List<SObject> records) {
            return new Accounts((List<Account>) records);
        }
    }

    public override void onApplyDefaults() {
        for (Account acc : (List<Account>) Records) {
            if (String.isBlank(acc.Industry)) {
                acc.Industry = 'Other';
            }
        }
    }

    public override void onValidate() {
        for (Account acc : (List<Account>) Records) {
            // addError on the record, not a thrown exception — this is what surfaces the
            // message on the right row in a bulk operation.
            if (acc.AnnualRevenue != null && acc.AnnualRevenue < 0) {
                acc.AnnualRevenue.addError('Annual Revenue cannot be negative.');
            }
        }
    }

    /** Runs on update. existingRecords is keyed by Id — use it, do not re-query. */
    public override void onValidate(Map<Id, SObject> existingRecords) {
        for (Account acc : (List<Account>) Records) {
            Account old = (Account) existingRecords.get(acc.Id);
            if (old != null && old.Name != acc.Name && acc.Name == null) {
                acc.Name.addError('Account Name cannot be cleared.');
            }
        }
    }
}
