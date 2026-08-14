/**
 * TEMPLATE — Service interface.
 *
 * The interface exists so callers depend on a contract and tests can inject a mock through
 * Application.Service.setMock(). A service class with no interface is untestable in isolation;
 * flag it in review.
 */
public interface IAccountsService {
    /**
     * Bulk-safe by contract: takes a collection, never a single record.
     * A service method that takes one record teaches callers to loop over it.
     */
    void reassignOwner(Set<Id> accountIds, Id newOwnerId);

    List<Account> byIndustry(String industry);
}
