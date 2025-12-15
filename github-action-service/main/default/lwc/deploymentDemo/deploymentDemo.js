import { LightningElement, track } from "lwc";
import triggerWorkflow from "@salesforce/apex/GitHubActionsService.triggerWorkflow";
import listWorkflows from "@salesforce/apex/GitHubActionsService.listWorkflows";
import { ShowToastEvent } from "lightning/platformShowToastEvent";

export default class DeploymentDemo extends LightningElement {
  @track isLoading = false;
  @track selectedEnvironment = "sandbox";
  @track deployTests = true;
  @track recordId = "";
  @track workflows = [];
  @track showWorkflows = false;
  @track debugInfo = "";

  // Configuration - Update these with your GitHub details
  owner = "gforceinnovation";
  repo = "sf-develop-demo";
  workflowFileName = "salesforce-deployment-demo.yml";
  branch = "main";

  get environmentOptions() {
    return [
      { label: "🏖️ Sandbox", value: "sandbox" },
      { label: "🎭 Staging", value: "staging" },
      { label: "🚀 Production", value: "production" }
    ];
  }

  get isDisabled() {
    return this.isLoading || !this.selectedEnvironment;
  }

  get repository() {
    return `${this.owner}/${this.repo}`;
  }

  get workflowCount() {
    return this.workflows ? this.workflows.length : 0;
  }

  handleEnvironmentChange(event) {
    this.selectedEnvironment = event.detail.value;
  }

  handleDeployTestsChange(event) {
    this.deployTests = event.target.checked;
  }

  handleRecordIdChange(event) {
    this.recordId = event.target.value;
  }

  async handleDeploy() {
    if (!this.selectedEnvironment) {
      this.showToast("Error", "Please select an environment", "error");
      return;
    }

    this.isLoading = true;
    this.debugInfo = "";

    try {
      // Get current user for triggered_by
      const currentUser = await this.getCurrentUserName();

      // Prepare workflow inputs
      const inputs = {
        environment: this.selectedEnvironment,
        deploy_tests: this.deployTests,
        triggered_by: currentUser
      };

      // Add record ID if provided
      if (this.recordId) {
        inputs.record_id = this.recordId;
      }

      // Prepare request
      const request = {
        owner: this.owner,
        repo: this.repo,
        workflowId: this.workflowFileName,
        ref: this.branch,
        inputs: inputs
      };

      this.debugInfo = `Triggering workflow...\n${JSON.stringify(request, null, 2)}`;

      // Call Apex method
      await triggerWorkflow(request);

      this.showToast(
        "Success! 🎉",
        `Deployment to ${this.selectedEnvironment} initiated. Check GitHub Actions for progress.`,
        "success"
      );

      this.debugInfo += "\n\n✅ Workflow triggered successfully!";
    } catch (error) {
      console.error("Error triggering workflow:", error);
      this.showToast("Error", this.getErrorMessage(error), "error");
      this.debugInfo = `Error: ${this.getErrorMessage(error)}`;
    } finally {
      this.isLoading = false;
    }
  }

  async handleListWorkflows() {
    this.isLoading = true;
    this.showWorkflows = false;
    this.debugInfo = "";

    try {
      const request = {
        owner: this.owner,
        repo: this.repo
      };

      this.debugInfo = `Listing workflows...\n${JSON.stringify(request, null, 2)}`;

      const result = await listWorkflows(request);

      this.workflows = result.workflows.map((wf) => ({
        id: wf.id,
        name: wf.name,
        path: wf.path,
        state: wf.state
      }));

      this.showWorkflows = true;
      this.showToast(
        "Success",
        `Found ${this.workflows.length} workflow(s)`,
        "success"
      );

      this.debugInfo += `\n\n✅ Found ${this.workflows.length} workflows`;
    } catch (error) {
      console.error("Error listing workflows:", error);
      this.showToast("Error", this.getErrorMessage(error), "error");
      this.debugInfo = `Error: ${this.getErrorMessage(error)}`;
    } finally {
      this.isLoading = false;
    }
  }

  async getCurrentUserName() {
    // In a real implementation, you could call an Apex method to get the current user's name
    // For this demo, we'll use a placeholder
    return "Salesforce User";
  }

  getErrorMessage(error) {
    if (error.body) {
      if (error.body.message) {
        return error.body.message;
      }
      if (error.body.pageErrors && error.body.pageErrors.length > 0) {
        return error.body.pageErrors[0].message;
      }
    }
    return error.message || "An unknown error occurred";
  }

  showToast(title, message, variant) {
    const event = new ShowToastEvent({
      title: title,
      message: message,
      variant: variant,
      mode: variant === "error" ? "sticky" : "dismissable"
    });
    this.dispatchEvent(event);
  }
}
