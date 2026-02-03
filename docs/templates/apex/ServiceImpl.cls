public with sharing class {{ServiceImpl}} implements {{ServiceInterface}} {
    public {{ReturnType}} {{methodName}}({{params}}) {
        fflib_ISObjectUnitOfWork uow = Application.UnitOfWork.newInstance();
        // TODO: use selectors and domains, register work in uow, then commit.
        return {{defaultReturn}};
    }
}
