# Terraform

### Overview

You can manage your CPLN configuration through `cpflow` commands and later invoke the generation of Terraform configuration files by running:

```sh
cpflow terraform generate
```

This command will create Terraform configurations for each application defined in `controlplane.yml`, utilizing templates from the `templates` folder.

Each time this command is invoked, Terraform configurations will be recreated, terraform lock file will be preserved. You can continue working with CPLN configuration files in YAML format and simply transform them to Terraform format at any time.

### Project Structure

Given the project structure below:

```
.controlplane/
├── templates/
│   ├── app.yml -- GVC config
│   ├── postgres.yml -- workload config
│   └── rails.yml -- workload config
├── controlplane.yml -- configs for overall application
├── Dockerfile -- Docker configuration for the application
└── entrypoint.sh -- Entry point script for the application
```

Invoking `cpflow terraform generate` will generate a new `terraform` folder with subfolders containing Terraform configurations for each application described in `controlplane.yml`:

```
.controlplane/
├── templates/
│   ├── app.yml -- GVC config
│   ├── postgres.yml -- workload config
│   └── rails.yml -- workload config
├── terraform/
│   ├── staging/ -- Terraform configurations for staging environment
│   │   ├── gvc.tf -- GVC config in HCL
│   │   ├── postgres.tf -- Postgres workload config in HCL
│   │   ├── postgres_envs.tf -- ENV variables for Postgres workload in HCL
│   │   ├── rails.tf -- Rails workload config in HCL
│   │   ├── rails_envs.tf -- ENV variables for Rails workload in HCL
│   │   ├── providers.tf -- Providers config in HCL
│   │   └── required_providers.tf -- Required providers config in HCL
│   ├── production/ -- Terraform configurations for production environment
│   │   ├── gvc.tf -- GVC config in HCL
│   │   ├── postgres.tf -- Postgres workload config in HCL
│   │   ├── postgres_envs.tf -- ENV variables for Postgres workload in HCL
│   │   ├── rails.tf -- Rails workload config in HCL
│   │   ├── rails_envs.tf -- ENV variables for Rails workload in HCL
│   │   ├── providers.tf -- Providers config in HCL
│   │   └── required_providers.tf -- Required providers config in HCL
│   ├── workload/ -- Terraform configurations for workload module
│   │   ├── main.tf -- Main config for workload resource in HCL
│   │   └── variables.tf -- Variables used to create config for workload resource in HCL
├── controlplane.yml -- configs for overall application
├── Dockerfile -- Docker configuration for the application
└── entrypoint.sh -- Entry point script for the application
```

### Terraform Configurations from CPLN Templates

#### Providers

Terraform provider configurations are controlled via `required_providers.tf` and `providers.tf`:

- **`required_providers.tf`**

```terraform
terraform {
  required_providers {
    cpln = {
      source = "controlplane-com/cpln"
      version = "~> 1.0"
    }
  }
}
```

- **`providers.tf`**

```terraform
provider "cpln" {
  org = "org-name-example"
}
```

#### GVC

CPLN template in YAML format:

```yaml
kind: gvc
name: app-name
description: app-description
tags:
  tag-name-1: "tag-value-1"
  tag-name-2: "tag-value-2"
spec:
  domain: "app.example.com"
  env:
    - name: DATABASE_URL
      value: "postgres://the_user:the_password@postgres.app-name.cpln.local:5432/app-name"
    - name: RAILS_ENV
      value: production
    - name: RAILS_SERVE_STATIC_FILES
      value: "true"
  staticPlacement:
    locationLinks:
      - "//location/aws-us-west-2"
  pullSecretLinks:
    - "/org/org-name/secret/some-secret"
  loadBalancer:
    dedicated: true
    trustedProxies: 0
```

Will transform to Terraform config:

```terraform
resource "cpln_gvc" "app-name" {
  name = "app-name"
  description = "app-description"
  tags = {
    tag_name_1 = "tag-value-1"
    tag_name_2 = "tag-value-2"
  }
  domain = "app.example.com"
  locations = ["aws-us-west-2"]
  pull_secrets = ["cpln_secret.some-secret.name"]
  env = {
    DATABASE_URL = "postgres://the_user:the_password@postgres.app-name.cpln.local:5432/app-name"
    RAILS_ENV = "production"
    RAILS_SERVE_STATIC_FILES = "true"
  }
  load_balancer {
    dedicated = true
    trusted_proxies = 0
  }
}
```

#### Identity

CPLN template in YAML format:

```yaml
kind: identity
name: postgres-poc-identity
description: postgres-poc-identity
tags:
  tag-name-1: "tag-value-1"
  tag-name-2: "tag-value-2"
```

Will transform to Terraform config:

```terraform
resource "cpln_identity" "postgres-poc-identity" {
  name = "postgres-poc-identity"
  description = "postgres-poc-identity"
  tags = {
    tag_name_1 = "tag-value-1"
    tag_name_2 = "tag-value-2"
  }
}
```

#### Secret

CPLN template in YAML format

**For `aws` secret:**

```yaml
kind: secret
name: aws
description: aws
type: aws
data:
  accessKey: 'AccessKeyExample'
  externalId: 'ExternalIdExample'
  roleArn: arn:awskey
  secretKey: 'SecretKeyExample'
```

Will transform to Terraform config:

```terraform
resource "cpln_secret" "aws" {
  name = "aws"
  description = "aws"
  aws {
    secret_key = "SecretKeyExample"
    access_key = "AccessKeyExample"
    role_arn = "arn:awskey"
    external_id = "ExternalIdExample"
  }
}
```

**For `azure-connector` secret:**

```yaml
kind: secret
name: azure-connector
description: azure_connector
tags:
  tag1: tag-val
type: azure-connector
data:
  code: 'CodeExample'
  url: https://example.com
```

Will transform to Terraform config:

```terraform
resource "cpln_secret" "azure-connector" {
  name = "azure-connector"
  description = "azure_connector"
  tags = {
    tag1 = "tag-val"
  }
  azure_connector {
    url = "https://example.com"
    code = "CodeExample"
  }
}
```

**For `azure-sdk-secret` secret:**

```yaml
kind: secret
name: azure-sdk-secret
description: azure-sdk-secret
type: azure-sdk
data: >-
  {"subscriptionId":"subscriptionId","tenantId":"tenantId","clientId":"clientId","clientSecret":"CONFIDENTIAL"}
```

Will transform to Terraform config:

```terraform
resource "cpln_secret" "azure-sdk-secret" {
  name = "azure-sdk-secret"
  description = "azure-sdk-secret"
  azure_sdk = "{"subscriptionId":"subscriptionId","tenantId":"tenantId","clientId":"clientID","clientSecret":"CONFIDENTIAL"}"
}
```

**For `dictionary` secret:**

```yaml
kind: secret
name: dictionary
description: dictionary
tags: {}
type: dictionary
data:
  example: 'value'
```

Will transform to Terraform config:

```terraform
resource "cpln_secret" "dictionary" {
  name = "dictionary"
  description = "dictionary"
  tags = {
  }
  dictionary = {
    example = "value"
  }
}
```

Supported all types of the secrets which can be configured in Control Plane.

#### Policy

CPLN template in YAML format:

```yaml
kind: policy
name: policy-name
description: policy description
tags:
  tag1: tag1_value
  tag2: tag2_value
target: all
targetKind: secret
targetLinks:
- "//secret/postgres-poc-credentials"
- "//secret/postgres-poc-entrypoint-script"
bindings:
  - permissions:
    - reveal
    - view
    - use
    principalLinks:
      - "//gvc/{{APP_NAME}}/identity/postgres-poc-identity"
  - permissions:
    - view
    principalLinks:
      - user/fake-user@fake-email.com
```

Will be transformed to Terraform config:

```terraform
resource "cpln_policy" "policy-name" {
  name = "policy-name"
  description = "policy description"
  tags = {
    tag1 = "tag1_value"
    tag2 = "tag2_value"
  }
  target_kind = "secret"
  gvc = cpln_gvc.app-name.name
  target = "all"
  target_links = ["postgres-poc-credentials", "postgres-poc-entrypoint-script"]
  binding {
    permissions = ["reveal", "view", "use"]
    principal_links = ["gvc/app-name/identity/postgres-poc-identity"]
  }
  binding {
    permissions = ["view"]
    principal_links = ["user/fake-user@fake-email.com"]
  }
}
```

#### Volumeset

CPLN template in YAML format:

```yaml
kind: volumeset
name: postgres-poc-vs
description: postgres-poc-vs
spec:
  autoscaling:
    maxCapacity: 1000
    minFreePercentage: 1
    scalingFactor: 1.1
  fileSystemType: ext4
  initialCapacity: 10
  performanceClass: general-purpose-ssd
  snapshots:
    createFinalSnapshot: true
    retentionDuration: 7d
```

Will be transformed to Terraform config:

```terraform
resource "cpln_volume_set" "postgres-poc-vs" {
  gvc = cpln_gvc.app-name.name
  name = "postgres-poc-vs"
  description = "postgres-poc-vs"
  initial_capacity = 10
  performance_class = "general-purpose-ssd"
  file_system_type = "ext4"
  snapshots {
    create_final_snapshot = true
    retention_duration = "7d"
  }
  autoscaling {
    max_capacity = 1000
    min_free_percentage = 1
    scaling_factor = 1.1
  }
}
```

#### Workload

CPLN template in YAML format:

```yaml
kind: workload
name: rails
spec:
  type: standard
  containers:
    - name: rails
      cpu: 300m
      env:
        - name: LOG_LEVEL
          value: debug
      inheritEnv: true
      image: {{APP_IMAGE_LINK}}
      memory: 512Mi
      ports:
        - number: 3000
          protocol: http
  defaultOptions:
    autoscaling:
      maxScale: 1
    capacityAI: false
  firewallConfig:
    external:
      # Default to allow public access to Rails server
      inboundAllowCIDR:
        - 0.0.0.0/0
      # Could configure outbound for more security
      outboundAllowCIDR:
        - 0.0.0.0/0
```

Will be transformed to Terraform configs:

- **`rails.tf`**

```terraform
module "rails" {
  source = "../workload"
  type = "standard"
  name = "rails"
  gvc = cpln_gvc.my-app-production.name
  containers = {
    rails: {
      image: "/org/shakacode-demo/image/my-app-production:rails",
      cpu: "300m",
      memory: "512Mi",
      inherit_env: true,
      envs: local.rails_envs,
      ports: [
        {
          number: 3000,
          protocol: "http"
        }
      ]
    }
  }
  options = {
    autoscaling: {
      max_scale: 1
    }
    capacity_ai: false
  }
  firewall_spec = {
    external: {
      inbound_allow_cidr: [
        "0.0.0.0/0"
      ],
      outbound_allow_cidr: [
        "0.0.0.0/0"
      ]
    }
  }
}
```

Notice `source: ../workload` line - there is common `workload` module which is used for generating Terraform configs from workload templates:
```
workload/
├── main.tf -- Configurable workload resource in HCL
├── variables.tf -- Variables used to configure workload resource above
```

- **`rails_envs.tf`**

```terraform
locals {
  rails_envs = {
    LOG_LEVEL = "debug"
  }
}
```

### References

- [Control Plane Terraform Provider](https://registry.terraform.io/providers/controlplane-com/cpln/latest/docs)
- [Terraform Provider Plugin](https://shakadocs.controlplane.com/terraform/installation#terraform-provider-plugin)
