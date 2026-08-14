# GForce LWC Coding Rules

Read this file before generating any Lightning Web Component code.

---

## 1. Template Conditionals

Always use `lwc:if` / `lwc:elseif` / `lwc:else`. The legacy `if:true` / `if:false` directives are deprecated.

**BAD**

```html
<template if:true="{isLoading}">
  <lightning-spinner></lightning-spinner>
</template>
<template if:false="{isLoading}">
  <p>Data loaded</p>
</template>
```

**GOOD**

```html
<template lwc:if="{isLoading}">
  <lightning-spinner
    alternative-text="Loading"
    size="small"
  ></lightning-spinner>
</template>
<template lwc:elseif="{hasError}">
  <p class="slds-text-color_error">{errorMessage}</p>
</template>
<template lwc:elseif="{isEmpty}">
  <p class="slds-text-color_weak">No records found.</p>
</template>
<template lwc:else>
  <!-- success state content -->
</template>
```

---

## 2. Four-State Template Pattern

Every data-driven component must handle all four states: loading, error, empty, success.

```html
<!-- myComponent.html -->
<template>
  <template lwc:if="{isLoading}">
    <lightning-spinner
      alternative-text="Loading"
      size="small"
    ></lightning-spinner>
  </template>
  <template lwc:elseif="{hasError}">
    <div class="slds-notify slds-notify_alert slds-alert_error" role="alert">
      <span class="slds-assistive-text">error</span>
      <p>{errorMessage}</p>
    </div>
  </template>
  <template lwc:elseif="{isEmpty}">
    <div class="slds-illustration slds-illustration_small">
      <p class="slds-text-color_weak">No records to display.</p>
    </div>
  </template>
  <template lwc:else>
    <template for:each="{records}" for:item="record">
      <div key="{record.Id}">{record.Name}</div>
    </template>
  </template>
</template>
```

```js
// myComponent.js
import { LightningElement, wire } from "lwc";
import getAccounts from "@salesforce/apex/AccountController.getAccounts";

export default class MyComponent extends LightningElement {
  records;
  errorMessage;
  isLoading = true;

  get hasError() {
    return !!this.errorMessage;
  }
  get isEmpty() {
    return (
      !this.isLoading &&
      !this.hasError &&
      (!this.records || this.records.length === 0)
    );
  }

  @wire(getAccounts)
  wiredAccounts({ data, error }) {
    this.isLoading = false;
    if (data) {
      this.records = data;
      this.errorMessage = undefined;
    } else if (error) {
      this.errorMessage = error.body?.message ?? "Unknown error";
      this.records = undefined;
    }
  }
}
```

---

## 3. Wire vs Imperative Apex

- **Wire** (`@wire`): for reads — reactive, cached by LDS, auto-refreshes
- **Imperative**: for mutations (insert/update/delete) or when you need to control timing

```js
// Wire — for reads
import { wire } from 'lwc';
import getAccounts from '@salesforce/apex/AccountController.getAccounts';

@wire(getAccounts, { industry: '$selectedIndustry' })
wiredAccounts({ data, error }) { ... }

// Imperative — for mutations or conditional calls
import saveAccount from '@salesforce/apex/AccountController.saveAccount';

async handleSave() {
    this.isLoading = true;
    try {
        await saveAccount({ accountId: this.accountId, name: this.name });
        this.dispatchEvent(new CustomEvent('save'));
    } catch (error) {
        this.errorMessage = error.body?.message ?? 'Save failed';
    } finally {
        this.isLoading = false;
    }
}
```

Always wrap imperative calls in `try/catch/finally`. Set `isLoading = false` in `finally`.

---

## 4. Events

- Event names: **lowercase only**, no camelCase (`accountselected` not `accountSelected`)
- Use `CustomEvent` with a `detail` payload
- Use `bubbles: true, composed: true` only when the event must cross shadow DOM boundaries

```js
// Fire event
this.dispatchEvent(new CustomEvent('accountselected', { detail: { accountId: this.accountId } }));

// Receive in parent template
<c-child-component onaccountselected={handleAccountSelected}></c-child-component>

// Handle in parent JS
handleAccountSelected(event) {
    const { accountId } = event.detail;
}
```

---

## 5. No Hardcoded Strings

All user-visible strings must use Custom Labels. No hardcoded text in templates or JS.

```js
// JS
import labelNoRecords from "@salesforce/label/c.No_Records_Found";
import labelSaveSuccess from "@salesforce/label/c.Save_Successful";

export default class MyComponent extends LightningElement {
  labels = { labelNoRecords, labelSaveSuccess };
}
```

```html
<!-- Template -->
<p>{labels.labelNoRecords}</p>
```

---

## 6. FLS Awareness

Never trust client-side FLS. FLS enforcement happens in Apex:

- Selectors use `WITH USER_MODE` or `Security.stripInaccessible`
- LWC never bypasses Apex to query directly
- Never use `@salesforce/schema` imports to write field values directly without Apex validation

For record forms, use `lightning-record-form`, `lightning-record-edit-form`, or `lightning-record-view-form` — these enforce FLS automatically via the UI API.

```html
<!-- Preferred for simple CRUD — FLS enforced automatically -->
<lightning-record-form
  record-id="{recordId}"
  object-api-name="Account"
  fields="{fields}"
  mode="edit"
  onsubmit="{handleSubmit}"
  onsuccess="{handleSuccess}"
>
</lightning-record-form>
```

---

## 7. SLDS First

Use SLDS utility classes and Lightning base components before writing custom CSS.

```html
<!-- Layout -->
<div class="slds-grid slds-wrap slds-gutters">
  <div class="slds-col slds-size_1-of-2">...</div>
</div>

<!-- Typography -->
<h2 class="slds-text-heading_medium">Title</h2>
<p class="slds-text-color_weak">Secondary text</p>

<!-- Spacing -->
<div class="slds-m-top_medium slds-p-around_small">...</div>
```

Custom CSS only when SLDS classes don't cover the need. All custom CSS in the component's `.css` file — never inline styles.

---

## 8. Navigation

Use `NavigationMixin` — never `window.location` or `window.open` for internal Salesforce navigation.

```js
import { NavigationMixin } from "lightning/navigation";

export default class MyComponent extends NavigationMixin(LightningElement) {
  navigateToRecord() {
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: { recordId: this.accountId, actionName: "view" }
    });
  }
}
```

---

## 9. Dialogs and Modals

Use `lightning/alert` and `lightning/confirm` — never `window.alert()` or `window.confirm()`.

```js
import LightningAlert from 'lightning/alert';
import LightningConfirm from 'lightning/confirm';

async handleDelete() {
    const confirmed = await LightningConfirm.open({
        message: 'Delete this account?',
        theme: 'warning',
        label: 'Confirm Delete'
    });
    if (confirmed) { /* proceed */ }
}
```

---

## 10. Performance

- Use `@wire` with LDS for record reads — it caches and avoids redundant server calls
- Avoid `renderedCallback` for data fetching — use `connectedCallback` or `@wire`
- Never mutate `@wire` data directly — clone it first: `this.records = [...data]`
- Use `for:each` with `key={item.Id}` — never use array index as key
- Lazy-load large child components with dynamic imports when above the fold is more important

---

## 11. Anti-Patterns

- `if:true` / `if:false` — use `lwc:if/elseif/else`
- `window.alert()` / `window.confirm()` — use `lightning/alert` and `lightning/confirm`
- Hardcoded strings in templates — use Custom Labels
- Inline styles — use SLDS classes or component CSS
- `window.location` for navigation — use NavigationMixin
- Missing `key` on `for:each` — always set `key`
- Catching errors without setting `errorMessage` — always surface errors to the user
- Mutating wire data directly — clone before modifying
- Mixing reads and writes in the same `@wire` handler
- Making imperative Apex calls in `connectedCallback` without a loading state
