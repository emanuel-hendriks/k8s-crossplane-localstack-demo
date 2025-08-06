# Cloud-Native Infrastructure with Docker Desktop Kubernetes, Crossplane, and Helm

## Overview

This task combines cloud-native technologies to create infrastructure using: 

- Docker Desktop Kubernetes, 
- Crossplane with Upbound providers for AWS resource provisioning, 
- Helm charts for application deployment

The setup demonstrates a complete event-driven architecture with producer and consumer applications communicating through AWS services (SNS, SQS) and storing data in DynamoDB, all running locally.

## Goals

- Create a cloud-native infrastructure using Docker Desktop Kubernetes
- Use Crossplane with Upbound AWS providers to provision AWS resources
- Deploy applications using Helm charts
- Set up a working event-driven architecture with producer and consumer applications

## Requirements

The solution needs to include:

- Docker Desktop Kubernetes cluster
- LocalStack Docker Desktop extension for simulating AWS services
- Crossplane with Upbound AWS provider for provisioning AWS resources
- AWS infrastructure provisioned through Crossplane (all resources must be in AWS region eu-central-1):
  - SNS topic named `justtrack-dev-devops-producer-events`
  - SQS queue named `justtrack-dev-devops-consumer-events`
  - Subscription from the queue to the topic
  - DynamoDB table named `justtrack-dev-devops-consumer-events` with an `Id` attribute of type string as hash key
- Applications deployed via Helm charts:
  - Producer application (`ghcr.io/justtrackio/devopstest-producer:latest`)
  - Consumer application (`ghcr.io/justtrackio/devopstest-consumer:latest`)
  - DynamoDB Admin for visualizing the DynamoDB data
- Applications need to be configured to connect to LocalStack with:
  - `CLOUD_AWS_DEFAULTS_ENDPOINT` environment variable

## Dependencies

- Docker Desktop 4.40.0 or newer with Kubernetes enabled
- LocalStack Docker Desktop extension
- kubectl command-line tool
- Helm package manager
- Container images:
  - `ghcr.io/justtrackio/devopstest-producer:latest`
  - `ghcr.io/justtrackio/devopstest-consumer:latest`

> **Note**: If you encounter the error `Failed to inspect image "": rpc error: code = Unknown desc = unable to convert a nil pointer to a runtime API image`, make sure that the Docker Desktop setting under General "Use containerd for pulling and storing images" is **not** enabled.

## Architecture

The architecture consists of:

1. **Infrastructure Layer**: Docker Desktop Kubernetes with Crossplane managing AWS resources in LocalStack
2. **Application Layer**: Producer and Consumer applications deployed as Kubernetes workloads via Helm
3. **Data Flow**:
   - Producer publishes events to SNS topic
   - Events are delivered to SQS queue via subscription
   - Consumer processes events from the queue and stores data in DynamoDB
   - DynamoDB Admin provides a web interface to view the stored data

## Evaluation Criteria

The solution will be evaluated based on:

1. Ability to work with Kubernetes
2. Understanding of Crossplane and ability to provision infrastructure
3. Ability to create and deploy Helm charts
4. Quality and completeness of the solution
5. Clarity of documentation