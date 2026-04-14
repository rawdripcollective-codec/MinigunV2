# Google Cloud Terraform App

This repository is a cleaned Terraform export of a Google Cloud application template.

## What is here

- `main.tf` — Cloud Run, BigQuery, AlloyDB, Redis, Pub/Sub, Vertex AI, and load balancer modules
- `providers.tf` — Google provider configuration
- `outputs.tf` — exported service endpoints and network outputs
- `versions.tf` — Terraform and provider version constraints

## Before you deploy

Replace any hard-coded project values if needed:

- `project_id = "artificial-creations"`
- `location = "us-central1"`

## Deploy

```bash
terraform init
terraform fmt
terraform plan
terraform apply
```

## Notes

The original export used hyphenated Terraform module labels and references. Those have been normalized to underscore style so the configuration is easier to validate in GitHub and CI.
