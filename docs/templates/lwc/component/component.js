import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getItems from '@salesforce/apex/{{ControllerName}}.getItems';
import saveItem from '@salesforce/apex/{{ControllerName}}.saveItem';

export default class {{ComponentName}} extends LightningElement {
    @api recordId;
    @track items = [];
    @track isLoading = false;
    wiredItemsResult;

    @wire(getItems, { searchTerm: '$recordId', limitCount: 10 })
    wiredGetItems(result) {
        this.wiredItemsResult = result;
        if (result.data) {
            this.items = result.data;
        } else if (result.error) {
            this.showToast('Error', result.error.body.message, 'error');
        }
    }

    async handleSave() {
        this.isLoading = true;
        try {
            await saveItem({ inputData: this.recordId });
            this.showToast('Success', 'Saved', 'success');
            await refreshApex(this.wiredItemsResult);
        } catch (error) {
            this.showToast('Error', error.body.message, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({
            title: title,
            message: message,
            variant: variant
        }));
    }
}
