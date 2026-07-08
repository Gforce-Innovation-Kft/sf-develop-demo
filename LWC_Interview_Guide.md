# Lightning Web Components (LWC) Interview Guide

## Core Concepts

### What is Lightning Web Components?
Lightning Web Components (LWC) is a modern framework for building user interfaces in Salesforce. It's built on standard web technologies like JavaScript ES6+, HTML, and CSS, and follows the component-based architecture pattern.

### Key Features
- Built on standard web technologies
- Faster performance compared to Aura components
- Component-based architecture
- Reactive programming model
- Built-in support for Lightning Design System (SLDS)

## Essential Terms

### 1. @api Decorator
- Used to expose properties and methods from a component to its parent
- Makes properties reactive and accessible from outside the component
- Example: `@api accountName;`

### 2. @track Decorator
- Used to make properties reactive for template updates
- When a tracked property changes, the template re-renders
- Example: `@track contactList = [];`

### 3. @wire Decorator
- Used for data fetching and reactive data loading
- Provides a declarative way to wire data from Apex or other sources
- Example: `@wire(getContacts, { accountId: '$accountId' }) contacts;`

### 4. Template Reference
- Used to reference elements in the component's HTML template
- Allows access to DOM elements for manipulation or event handling
- Example: `@api myRef;` in JS, referenced as `<template if:true={showContent} data-ref="myRef">`

### 5. Event Handling
- Communication between parent and child components
- Child components fire events that parent components listen to
- Use `this.dispatchEvent(new CustomEvent('eventName', { detail: data }));`

### 6. Lifecycle Hooks
- Methods that are called at specific points in a component's life cycle
- `connectedCallback()`: Called when component is inserted into DOM
- `renderedCallback()`: Called after every render
- `disconnectedCallback()`: Called when component is removed from DOM

### 7. Data Binding
- Unidirectional data flow from parent to child
- Uses the `@api` decorator for parent-to-child communication
- Uses events for child-to-parent communication

### 8. Slots
- Used for content projection in components
- Allow parent components to insert content into child components
- Example: `<slot name="footer"></slot>`

### 9. Shadow DOM
- Encapsulation mechanism that isolates component styles and markup
- Prevents CSS leakage between components
- Ensures component styling doesn't affect other parts of the page

### 10. Lightning Design System (SLDS)
- Salesforce's design system for consistent UI components
- Provides pre-built CSS classes for styling
- Ensures applications follow Salesforce design guidelines

## Common Patterns

### 1. Component Communication
- Parent to Child: Using `@api` properties
- Child to Parent: Using Custom Events
- Sibling to Sibling: Through parent component

### 2. Data Fetching
- Using `@wire` decorator with Apex methods
- Using `@wire` with standard Salesforce APIs
- Manual data fetching with Promise-based approaches

### 3. Conditional Rendering
- Using `if:true` and `if:false` directives
- Dynamic class binding with `class.*` syntax
- Conditional attribute binding

### 4. Iteration
- Using `for:each` directive with `key` attribute
- Efficient rendering of lists of data

## Best Practices

### Performance
- Use `@track` only for properties that need to trigger re-renders
- Avoid heavy computations in templates
- Use `@wire` for data fetching to take advantage of caching

### Security
- Always validate and sanitize data before use
- Use proper error handling
- Follow Salesforce security best practices

### Maintainability
- Keep components small and focused
- Use descriptive names for properties and methods
- Follow naming conventions consistently

## Structured Interview Answers (Cheat Sheet)

### Decorators and Data
- `@api`: Public reactive props/methods for parent → child. Mention that updates re-render. Use for public methods too.
- `@track`: Legacy deep reactivity. Prefer immutable updates or spreads; use only when mutating nested state.
- `@wire`: Declarative, reactive data; auto-refresh on param change; supports imperative `refreshApex`. Handle `data` and `error`.

### Lifecycle (order and usage)
- constructor → connectedCallback → renderedCallback (can repeat) → disconnectedCallback → errorCallback.
- Guidance: avoid DOM access in constructor; init in connectedCallback; guard renderedCallback to prevent loops; clean up listeners/timers in disconnectedCallback.

### Component Communication
- Parent → Child: `@api` props.
- Child → Parent: `CustomEvent('eventname', { detail })`; lowercase names; set `bubbles`/`composed` when needed.
- Sibling/Unrelated: Lightning Message Service (LMS) with message channels.

### Data Access (LDS vs Apex)
- Prefer Lightning Data Service (`getRecord`, `getRecordUi`, `updateRecord`, record forms) for CRUD/FLS/sharing.
- Use Apex for complex queries, aggregates, non-standard objects, or business logic. Keep wire params lightweight and stable.

### Performance
- Compute in JS getters, not inline template expressions.
- Paginate or lazy-load large lists; avoid massive DOM trees; consider virtualization.
- Avoid heavy work in `renderedCallback`; debounce expensive operations.
- Minimize DOM queries; prefer template refs.

### Styling and SLDS
- Use SLDS utility classes; avoid global CSS leaks.
- Shadow DOM scoping: use `:host` carefully; do not fight SLDS tokens unless needed.

### Testing
- Jest: render with `createElement`, await `flushPromises`, assert DOM and events.
- Apex interactions: mock wire adapters and imperative Apex imports.

### Security
- Enforce CRUD/FLS in Apex; LDS enforces automatically.
- Avoid SOQL injection (bind variables); avoid unsafe `innerHTML`; use `lightning-formatted-rich-text` when rendering rich text.
- Use `with sharing`/`inherited sharing` appropriately.

### Error Handling and UX
- Wires: check `error` vs `data`; show toasts for user-facing issues.
- Imperative calls: try/catch; surface friendly messages; log technical details separately.
- Cancel or ignore stale async work when params change.

### Common Interview Q&A (concise)
- Q: `@api` vs `@track` vs `@wire`? A: Public/reactive; legacy deep reactivity; declarative data with auto-refresh.
- Q: Lifecycle order? A: constructor → connectedCallback → renderedCallback (repeat) → disconnectedCallback → errorCallback; note where to init, render, and clean up.
- Q: Parent/child/sibling comms? A: `@api` props, CustomEvent, LMS.
- Q: When LDS vs Apex? A: LDS for CRUD/FLS/sharing simplicity; Apex for complex logic/queries/aggregates/non-standard objects.
- Q: Handling large data? A: Pagination, lazy load, virtualization, cache, avoid heavy DOM and inline computation.
- Q: Security musts? A: CRUD/FLS, with sharing, bind vars to avoid injection, no unsafe HTML.

### Advanced Mentions (optional in interviews)
- LMS for cross-DOM; `refreshApex`/`getRecordNotifyChange` for cache sync.
- Dynamic imports where supported.
- Accessibility: ARIA labels, keyboard nav, focus management, contrast.

## Examples (Reactivity and State)

### 1) Primitives are reactive by default
```js
import { LightningElement, api } from 'lwc';

export default class PrimitiveReactive extends LightningElement {
	@api greeting = 'Hello';

	handleChange(event) {
		this.greeting = event.target.value; // primitive assignment triggers re-render
	}
}
```

```html
<template>
	<lightning-input label="Greeting" value={greeting} onchange={handleChange}></lightning-input>
	<p>{greeting}, world!</p>
</template>
```

### 2) Mutating nested state needs @track (legacy deep reactivity)
```js
import { LightningElement, track } from 'lwc';

export default class TrackedNested extends LightningElement {
	@track profile = { name: 'Ada', title: 'Engineer' };

	promote() {
		this.profile.title = 'Staff Engineer'; // tracked nested change re-renders
	}
}
```

```html
<template>
	<p>{profile.name} — {profile.title}</p>
	<lightning-button label="Promote" onclick={promote}></lightning-button>
</template>
```

### 3) Immutable updates avoid @track for nested data
```js
import { LightningElement } from 'lwc';

export default class ImmutableNested extends LightningElement {
	profile = { name: 'Ada', title: 'Engineer' };

	promote() {
		this.profile = { ...this.profile, title: 'Staff Engineer' }; // new object triggers re-render
	}
}
```

```html
<template>
	<p>{profile.name} — {profile.title}</p>
	<lightning-button label="Promote" onclick={promote}></lightning-button>
</template>
```
