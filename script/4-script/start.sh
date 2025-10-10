#!/bin/bash

# Load environment variables if .env exists
if [ -f .env ]; then
    source .env
fi

# Check required environment variables
if [ -z "$SIDECAR_URL" ]; then
    echo "Error: SIDECAR_URL is not set"
    exit 1
fi

if [ -z "$ZEUS_DEPLOYED_AllocationManager_Proxy" ]; then
    echo "Error: ZEUS_DEPLOYED_AllocationManager_Proxy is not set"
    exit 1
fi

if [ -z "$RPC_URL" ]; then
    echo "Error: RPC_URL is not set"
    exit 1
fi

if [ -z "$PRIVATE_KEY" ]; then
    echo "Error: PRIVATE_KEY is not set"
    exit 1
fi

# Run the script
go run .