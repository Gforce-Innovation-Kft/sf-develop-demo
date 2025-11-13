#!/bin/bash

# Script to test Salesforce CLI operations using official Docker image
# This helps debug JWT authentication and scratch org creation issues

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if .env file exists
if [ ! -f ".env" ]; then
    print_error ".env file not found! Please create it with your Salesforce credentials."
    exit 1
fi

# Check if JWT key file exists
if [ ! -f "certs/server.key" ]; then
    print_error "certs/server.key file not found! Please ensure the certificate file exists."
    exit 1
fi

# Load environment variables
print_status "Loading environment variables from .env file..."
source .env

# Validate required environment variables
required_vars=("DEVHUB_CLIENT_ID" "DEVHUB_INSTANCE_URL" "DEVHUB_USERNAME")
for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        print_error "Required environment variable $var is not set in .env file"
        exit 1
    fi
done

print_status "Environment variables loaded:"
echo "  DEVHUB_USERNAME: $DEVHUB_USERNAME"
echo "  DEVHUB_CLIENT_ID: $DEVHUB_CLIENT_ID"
echo "  DEVHUB_INSTANCE_URL: $DEVHUB_INSTANCE_URL"

# Pull latest Salesforce Docker image
print_status "Pulling latest Salesforce CLI Docker image..."
docker pull salesforce/salesforcedx:latest-full

# Create a unique scratch org alias
SCRATCH_ORG_ALIAS="test-docker-$(date +%s)"
print_status "Using scratch org alias: $SCRATCH_ORG_ALIAS"

# Create the Docker run command
print_status "Starting Salesforce CLI container..."
print_status "Mounting current directory as /workspace in container..."

docker run --rm -it \
    -v "$(pwd):/workspace" \
    -w /workspace \
    --env-file .env \
    salesforce/salesforcedx:latest-full \
    /bin/bash -c "
        set -e
        
        echo '🔧 Salesforce CLI Version:'
        sf version
        
        echo ''
        echo '� Listing workspace contents:'
        ls -la
        
        echo ''
        echo '�🔑 Authenticating to Dev Hub with JWT...'
        sf org login jwt \
            --username '$DEVHUB_USERNAME' \
            --jwt-key-file certs/server.key \
            --client-id '$DEVHUB_CLIENT_ID' \
            --alias devhub \
            --set-default-dev-hub \
            --instance-url '$DEVHUB_INSTANCE_URL'
        
        echo ''
        echo '✅ Authentication successful! Dev Hub info:'
        sf org display --target-org devhub --verbose
            
        
        echo ''
        echo '🧪 Creating scratch org...'
        if [ -f 'config/project-scratch-def.json' ]; then
            sf org create scratch \
                --definition-file config/project-scratch-def.json \
                --alias '$SCRATCH_ORG_ALIAS' \
                --target-dev-hub devhub \
                --duration-days 1 \
                --wait 10
        else
            echo 'Using default scratch org definition...'
            sf org create scratch \
                --alias '$SCRATCH_ORG_ALIAS' \
                --target-dev-hub devhub \
                --duration-days 1 \
                --wait 10
        fi
        
        echo ''
        echo '✅ Scratch org created successfully!'
        sf org display --target-org '$SCRATCH_ORG_ALIAS'
        
        echo ''
        echo '🧹 Cleaning up scratch org...'
        sf org delete scratch --target-org '$SCRATCH_ORG_ALIAS' --no-prompt
        
        echo ''
        echo '🎉 All tests completed successfully!'
    "

print_status "Docker test completed! If this works, your JWT setup should work in GitHub Actions too."