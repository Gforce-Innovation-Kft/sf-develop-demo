/**
 * TEMPLATE — Selector layer.
 *
 * Adapt this shape; do not invent a different one. Uses only standard Account fields so it
 * compiles in any org.
 *
 * The one thing people get wrong: the constructor. fflib_SObjectSelector defaults to
 * DataAccess.LEGACY, which emits NO security clause. Without the constructor below, every
 * query in this class runs in system mode with no FLS, CRUD or sharing enforcement.
 */
public inherited sharing class AccountsSelector extends fflib_SObjectSelector {
    /**
     * REQUIRED. Args: includeFieldSetFields, enforceCRUD, enforceFLS, sortSelectFields, dataAccess.
     * DataAccess.USER_MODE is what makes generated SOQL end in WITH USER_MODE.
     */
    public AccountsSelector() {
        super(false, true, true, true, DataAccess.USER_MODE);
    }

    public static AccountsSelector newInstance() {
        return (AccountsSelector) Application.Selector.newInstance(Account.SObjectType);
    }

    public Schema.SObjectType getSObjectType() {
        return Account.SObjectType;
    }

    /** The default field list. Enumerate explicitly — never SELECT *. */
    public List<Schema.SObjectField> getSObjectFieldList() {
        return new List<Schema.SObjectField>{
            Account.Id,
            Account.Name,
            Account.Industry,
            Account.AnnualRevenue,
            Account.OwnerId,
            Account.CreatedDate
        };
    }

    public List<Account> selectById(Set<Id> idSet) {
        return (List<Account>) selectSObjectsById(idSet);
    }

    /**
     * Custom query. newQueryFactory() inherits the DataAccess setting from the constructor,
     * so there is no per-query security flag to remember.
     *
     * Always bind (:industry) — never concatenate input into the condition string.
     */
    public List<Account> selectByIndustry(String industry, Integer limitCount) {
        fflib_QueryFactory qf = newQueryFactory();
        qf.setCondition('Industry = :industry');
        qf.addOrdering(Account.Name, fflib_QueryFactory.SortOrder.ASCENDING);

        // Bound queries only. An unbounded selector is a governor limit waiting to happen.
        qf.setLimit(limitCount != null && limitCount > 0 ? limitCount : 200);

        return (List<Account>) Database.query(qf.toSOQL());
    }
}
