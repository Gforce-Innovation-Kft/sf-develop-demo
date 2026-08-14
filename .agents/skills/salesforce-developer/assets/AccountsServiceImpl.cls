/**
 * TEMPLATE — Service implementation.
 *
 * Register in Application.cls:
 *   IAccountsService.class => AccountsServiceImpl.class
 *
 * Rules this template demonstrates:
 *   - no SOQL here (that is the Selector's job)
 *   - no direct DML here (that is the Unit of Work's job)
 *   - guard clause on null/empty input before any work
 *   - Logger.* for logging, never System.debug
 */
public with sharing class AccountsServiceImpl implements IAccountsService {
    public void reassignOwner(Set<Id> accountIds, Id newOwnerId) {
        // Entry guard. Cheap, and it removes a whole class of NullPointerException.
        if (accountIds == null || accountIds.isEmpty() || newOwnerId == null) {
            return;
        }

        fflib_ISObjectUnitOfWork uow = Application.UnitOfWork.newInstance();

        // One query, before the loop. Never inside it.
        for (Account acc : AccountsSelector.newInstance().selectById(accountIds)) {
            acc.OwnerId = newOwnerId;
            uow.registerDirty(acc);
        }

        // Single commit for the whole batch — one DML statement regardless of volume.
        uow.commitWork();

        Logger.info('Reassigned ' + accountIds.size() + ' account(s) to ' + newOwnerId);
        Logger.saveLog();
    }

    public List<Account> byIndustry(String industry) {
        if (String.isBlank(industry)) {
            return new List<Account>();
        }
        return AccountsSelector.newInstance().selectByIndustry(industry, 200);
    }
}
