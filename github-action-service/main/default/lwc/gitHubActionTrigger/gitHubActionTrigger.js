import { LightningElement, track } from "lwc";
import triggerWorkflow from "@salesforce/apex/GitHubActionsService.triggerWorkflow";
import listWorkflows from "@salesforce/apex/GitHubActionsService.listWorkflows";
import { ShowToastEvent } from "lightning/platformShowToastEvent";

export default class GitHubActionTrigger extends LightningElement {
  @track isLoading = false;
  @track workflowList = [];
  @track debugInfo = "";
  @track showDebug = false;

  owner = "Gforce-Innovation-Kft";
  repo = "sf-develop-demo";

  // Configure your workflows here
  workflows = [
    {
      label: "Deploy to Staging",
      icon: "utility:upload",
      variant: "brand",
      owner: "Gforce-Innovation-Kft",
      repo: "sf-develop-demo",
      workflowId: "deploy-staging.yml",
      ref: "main"
    },
    {
      label: "Run Tests",
      icon: "utility:check",
      variant: "success",
      owner: "Gforce-Innovation-Kft",
      repo: "sf-develop-demo",
      workflowId: "run-tests.yml",
      ref: "main"
    },
    {
      label: "Build Package",
      icon: "utility:package",
      variant: "neutral",
      owner: "Gforce-Innovation-Kft",
      repo: "sf-develop-demo",
      workflowId: "build-package.yml",
      ref: "main"
    }
  ];

  handleTriggerWorkflow(event) {
    const workflowIndex = event.currentTarget.dataset.index;
    const workflow = this.workflows[workflowIndex];

    this.isLoading = true;

    const request = {
      owner: workflow.owner,
      repo: workflow.repo,
      workflowId: workflow.workflowId,
      ref: workflow.ref,
      inputs: {
        triggered_by: "Salesforce",
        timestamp: new Date().toISOString()
      }
    };

    triggerWorkflow({ request })
      .then((result) => {
        this.showToast("Success", result, "success");
      })
      .catch((error) => {
        this.showToast(
          "Error",
          error.body?.message || "Failed to trigger workflow",
          "error"
        );
      })
      .finally(() => {
        this.isLoading = false;
      });
  }

  handleListWorkflows() {
    this.isLoading = true;
    this.debugInfo = "";
    this.workflowList = [];
    this.showDebug = true;

    listWorkflows({ owner: this.owner, repo: this.repo })
      .then((result) => {
        const response = JSON.parse(result);
        this.debugInfo =
          "Connection successful! Found " +
          response.total_count +
          " workflow(s).\\n\\n";

        if (response.workflows && response.workflows.length > 0) {
          this.workflowList = response.workflows.map((wf) => {
            return {
              id: wf.id,
              name: wf.name,
              path: wf.path,
              state: wf.state,
              url: wf.html_url
            };
          });

          this.debugInfo += "Workflows:\\n";
          this.workflowList.forEach((wf) => {
            this.debugInfo += `- ${wf.name} (${wf.path}) - ${wf.state}\\n`;
          });
        } else {
          this.debugInfo += "No workflows found in this repository.\\n";
          this.debugInfo +=
            "Create a .github/workflows/ directory with workflow YAML files.";
        }

        this.showToast(
          "Success",
          "Successfully connected to GitHub API",
          "success"
        );
      })
      .catch((error) => {
        this.debugInfo = "Error connecting to GitHub:\\n\\n";
        this.debugInfo +=
          error.body?.message || error.message || "Unknown error";
        this.showToast(
          "Error",
          error.body?.message || "Failed to list workflows",
          "error"
        );
      })
      .finally(() => {
        this.isLoading = false;
      });
  }

  showToast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }
}
