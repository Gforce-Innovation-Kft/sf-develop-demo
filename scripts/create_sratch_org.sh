#!/bin/bash

# Weather Dashboard Demo - Scratch Org Creation & Deployment Script
# This script creates a scratch org, deploys the weather dashboard, and assigns permissions

set -e  # Exit on any error

# Configuration
SCRATCH_ORG_ALIAS="${1:-weather-demo}"
DEV_HUB_ALIAS="${2:-$(sf config get target-dev-hub --json 2>/dev/null | jq -r '.result[0].value // "devhub"')}"
DURATION_DAYS="${3:-2}"
# Multiple permission sets to assign
PERMISSION_SETS=("Weather_Dashboard_Demo_Access" "GitHub_Integration_Admin")

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
print_status "Checking prerequisites..."

if ! command_exists sf; then
    print_error "Salesforce CLI (sf) is not installed. Please install it first."
    exit 1
fi

# Check for Dev Hub
if [ -z "$DEV_HUB_ALIAS" ] || [ "$DEV_HUB_ALIAS" = "null" ]; then
    print_error "No Dev Hub specified. Please:"
    echo "  Usage: ./create_sratch_org.sh [scratch-org-alias] [dev-hub-alias] [duration-days]"
    echo "  1. Set default dev hub: sf config set target-dev-hub <your-dev-hub-alias>"
    echo "  2. Or run with parameters: ./create_sratch_org.sh weather-demo devhub 7"
    echo "  3. Or check available orgs: sf org list"
    exit 1
fi

print_status "Using Dev Hub: $DEV_HUB_ALIAS"

# Check if we're in the right directory
if [ ! -f "sfdx-project.json" ]; then
    print_error "sfdx-project.json not found. Please run this script from the project root directory."
    exit 1
fi

# Check for weather-app directory
if [ ! -d "weather-app" ]; then
    print_error "weather-app directory not found. Please ensure the project structure is correct."
    exit 1
fi

print_success "Prerequisites check passed!"

# Step 1: Create Scratch Org
print_status "Creating scratch org with alias '$SCRATCH_ORG_ALIAS'..."

sf org create scratch \
    --definition-file config/project-scratch-def.json \
    --alias "github1" \
    --target-dev-hub "gabor_dev" \
    --duration-days "10" \
    --set-default \
    --wait 10

if [ $? -eq 0 ]; then
    print_success "Scratch org '$SCRATCH_ORG_ALIAS' created successfully!"
else
    print_error "Failed to create scratch org. Please check your Dev Hub connection."
    exit 1
fi

# Step 2: Load Environment Variables
print_status "Loading environment variables from .env file..."

# Check if .env file exists
if [ -f ".env" ]; then
    print_success "Found .env file, loading variables..."

    # Export variables from .env file
    set -a
    source .env
    set +a

    # Check for required variables
    if [ -n "$GITHUB_PRIVATE_KEY_BASE64" ]; then
        print_success "✅ GITHUB_PRIVATE_KEY_BASE64 loaded (${#GITHUB_PRIVATE_KEY_BASE64} chars)"
    else
        print_warning "⚠️  GITHUB_PRIVATE_KEY_BASE64 not found in .env"
    fi

    # List other loaded variables (without values)
    echo ""
    echo "Environment variables loaded from .env:"
    grep -v '^#' .env | grep -v '^$' | cut -d '=' -f1 | while read -r var; do
        if [ -n "${!var}" ]; then
            echo "  ✅ $var"
        fi
    done
    echo ""
else
    print_warning ".env file not found - skipping environment variable injection"
    print_warning "Create .env file with GITHUB_PRIVATE_KEY_BASE64 for string replacement"
fi

# Step 3: Push Source Code with String Replacement
print_status "Deploying source code to scratch org..."
print_status "SFDX will replace placeholders with environment variables..."

sf project deploy start --source-dir weather-app 

if [ $? -eq 0 ]; then
    print_success "Source code deployed successfully!"
    if [ -f ".env" ]; then
        print_success "String replacements applied from environment variables!"
    fi
else
    print_error "Failed to deploy source code."
    exit 1
fi

# Step 4: Assign Permission Sets
print_status "Assigning permission sets..."

PERMSET_SUCCESS=true

for PERMSET in "${PERMISSION_SETS[@]}"; do
    print_status "Assigning permission set: $PERMSET"

    if sf org assign permset --name "$PERMSET" 2>/dev/null; then
        print_success "✅ Assigned: $PERMSET"
    else
        print_warning "⚠️  Failed to assign: $PERMSET (may not exist in this org)"
        PERMSET_SUCCESS=false
    fi
done

if [ "$PERMSET_SUCCESS" = true ]; then
    print_success "All permission sets assigned successfully!"
else
    print_warning "Some permission sets could not be assigned. You may need to assign them manually."
fi

# Step 5: Open the Org
print_status "Opening scratch org..."

sf org open --path "/lightning/n/Weather"

# Step 6: Display Summary
echo ""
print_success "🎉 Weather Dashboard Demo Setup Complete!"
echo ""
echo -e "${BLUE}Scratch Org Details:${NC}"
echo "  • Alias: $SCRATCH_ORG_ALIAS"
echo "  • Duration: $DURATION_DAYS days"
echo "  • Permission Sets: ${PERMISSION_SETS[*]}"
echo ""
echo -e "${BLUE}Next Steps:${NC}"
echo "  1. Update API key in WeatherServiceImpl.cls"
echo "  2. Navigate to Weather Dashboard tab"
echo "  3. Enter a city name (e.g., 'London')"
echo "  4. Click 'Get Current Weather'"
echo ""
echo -e "${BLUE}Access URLs:${NC}"
echo "  • Weather Dashboard: /lightning/n/Weather_Dashboard"
echo "  • Weather Reports: /lightning/o/Weather_Report__c/list"
echo "  • Setup: /lightning/setup/SetupOneHome/home"
echo ""
echo -e "${YELLOW}Remember:${NC} Get your free API key from https://openweathermap.org/api"
echo ""

# Step 7: Display org info
print_status "Getting org information..."
sf org display --target-org "$SCRATCH_ORG_ALIAS"

print_success "Script completed successfully! 🚀"