# Terraform

## Overview

You can manage your Control Plane (CPLN) configuration through `cpflow` commands and later invoke the generation of Terraform configuration files by running:

```sh
cpflow terraform generate
```

This command will create Terraform configurations for each application defined in `controlplane.yml`, utilizing templates from the `templates` folder.

Each time this command is invoked, Terraform configurations will be recreated, and the Terraform lock file will be preserved.

You can continue working with CPLN configuration files in YAML format and simply transform them to Terraform format at any time.

## Benefits of Using Terraform Over YAML Configs

1. **State Management**: Terraform maintains a state file that tracks the current state of your infrastructure, making it easier to manage changes and updates.
2. **Dependency Management**: Terraform automatically handles dependencies between resources, ensuring that they are created or destroyed in the correct order.
3. **Multi-Cloud Support**: With Terraform, you can manage resources across multiple cloud providers seamlessly, allowing for a more flexible architecture.
4. **Plan and Apply**: Terraform provides a clear plan of what changes will be made before applying them, reducing the risk of unintended modifications.

## Usage

Suppose that you have CPLN configurations in YAML format for a Rails application with the following project structure (see the `example` folder):

```
.controlplane/
├── templates/
│   ├── app.yml -- GVC config
│   ├── postgres.yml -- Workload config for PostgreSQL
│   └── rails.yml -- Workload config for Rails
└── controlplane.yml -- Configs for overall application
```

- **`controlplane.yml`**
```yaml
allow_org_override_by_env: true
allow_app_override_by_env: true

aliases:
  common: &common
    cpln_org: my-org-staging
    default_location: aws-us-east-2
    setup_app_templates:
      - app
      - postgres
      - rails
    one_off_workload: rails
    app_workloads:
      - rails
    additional_workloads:
      - postgres
apps:
  rails-app-staging:
    <<: *common
    hooks:
      post_creation: bundle exec rake db:prepare
      pre_deletion: bundle exec rake db:drop

  rails-app-production:
    <<: *common
    allow_org_override_by_env: false
    allow_app_override_by_env: false
    cpln_org: my-org-production
    upstream: rails-app-staging
```
**Description**: This file defines the overall configuration for the Rails application, including organization settings, environment variables, and application-specific hooks for managing database tasks during deployment.

- **`app.yml`**
```yaml
kind: gvc
name: {{APP_NAME}}
description: Global Virtual Cloud for Rails Application
spec:
  env:
    - name: DATABASE_URL
      value: "postgres://user:password@postgres.{{APP_NAME}}.cpln.local:5432/{{APP_NAME}}"
    - name: RAILS_ENV
      value: production
    - name: RAILS_SERVE_STATIC_FILES
      value: "true"
  staticPlacement:
    locationLinks:
      - {{APP_LOCATION_LINK}}
  pullSecretLinks:
    - "/org/org-name/secret/rails-app-secret"
  loadBalancer:
    dedicated: true
    trustedProxies: 0

---

kind: identity
name: rails-app-identity
description: Identity for Rails Application
tags:
  environment: production

---

kind: secret
name: rails-app-secret
description: Secret for Rails Application
type: aws
data:
  accessKey: 'AccessKeyExample'
  secretKey: 'SecretKeyExample'
  region: 'us-west-2'
```
**Description**: This file defines the Global Virtual Cloud (GVC) configuration, including environment variables for the Rails application, identity settings, and AWS secrets for accessing resources.

- **`postgres.yml`**
```yaml
kind: workload
name: postgres
spec:
  type: standard
  containers:
    - name: postgres
      cpu: 500m
      env:
        - name: POSTGRES_USER
          value: "user"
        - name: POSTGRES_PASSWORD
          value: "password"
        - name: POSTGRES_DB
          value: "rails_app"
      inheritEnv: true
      image: "postgres:latest"
      memory: 1Gi
      ports:
        - number: 5432
          protocol: tcp
  defaultOptions:
    autoscaling:
      maxScale: 1
    capacityAI: false
  firewallConfig:
    external:
      inboundAllowCIDR:
        - 0.0.0.0/0
      outboundAllowCIDR:
        - 0.0.0.0/0
```
**Description**: This file defines a workload resource for the PostgreSQL database, specifying the container image, CPU and memory allocation, environment variables, and firewall rules.

- **`rails.yml`**
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
      image: "org-name/rails:latest"
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
      inboundAllowCIDR:
        - 0.0.0.0/0
      outboundAllowCIDR:
        - 0.0.0.0/0
```
**Description**: This file defines a workload resource for the Rails application, including the container image, CPU and memory allocation, environment variables, and firewall rules.

## Generating Terraform Configurations

To generate Terraform configurations, run the command below:

```sh
cpflow terraform generate
```

Invoking this command will generate a new `terraform` folder with subfolders containing Terraform configurations for each application described in `controlplane.yml`:

```
.controlplane/
├── templates/
│   ├── app.yml -- GVC config
│   ├── postgres.yml -- Workload config for PostgreSQL
│   └── rails.yml -- Workload config for Rails
├── terraform/
│   ├── rails-app-production/ -- Terraform configurations for production environment
│   │   ├── gvc.tf -- GVC config in HCL
│   │   ├── postgres.tf -- Postgres workload config in HCL
│   │   ├── postgres_envs.tf -- ENV variables for Postgres workload in HCL
│   │   ├── rails-app.tf -- Rails workload config in HCL
│   │   ├── rails_envs.tf -- ENV variables for Rails workload in HCL
│   │   ├── providers.tf -- Providers config in HCL
│   │   └── required_providers.tf -- Required providers config in HCL
│   ├── rails-app-staging/ -- Terraform configurations for staging environment
│   │   ├── gvc.tf -- GVC config in HCL
│   │   ├── postgres.tf -- Postgres workload config in HCL
│   │   ├── postgres_envs.tf -- ENV variables for Postgres workload in HCL
│   │   ├── rails-app.tf -- Rails workload config in HCL
│   │   ├── rails_envs.tf -- ENV variables for Rails workload in HCL
│   │   ├── providers.tf -- Providers config in HCL
│   │   └── required_providers.tf -- Required providers config in HCL
│   ├── workload/ -- Terraform configurations for workload module
│   │   ├── main.tf -- Main config for workload resource in HCL
│   │   ├── required_providers.tf -- Required providers for Terraform in HCL
│   │   └── variables.tf -- Variables used to create config for workload resource in HCL
├── controlplane.yml -- Configs for overall application
```

Each subfolder is a separate Terraform module, allowing you to manage the deployment of different environments of your application (e.g., `staging` and `production`).

Let's take a look at the Terraform configurations for the `rails-app-staging` application, along with descriptions for each generated file to help you understand their purpose.

## Terraform Configurations for `rails-app-staging`

- **`gvc.tf`**
```hcl
resource "cpln_gvc" "rails-app-staging" {
  name = "rails-app-staging"
  description = "Global Virtual Cloud for Rails Application"
  locations = ["aws-us-east-2"]
  pull_secrets = [cpln_secret.rails-app-secret.name]
  env = {
    DATABASE_URL = "postgres://user:password@postgres.rails-app-staging.cpln.local:5432/rails-app-staging"
    RAILS_ENV = "production"
    RAILS_SERVE_STATIC_FILES = "true"
  }
  load_balancer {
    dedicated = true
    trusted_proxies = 0
  }
}
```
**Description**: This file defines a Global Virtual Cloud (GVC) resource for the Rails application. It specifies the name, description, and location of the GVC. The `pull_secrets` field links to the secret needed for accessing the cloud resources. The `env` block sets environment variables that the application will use, such as the database URL and Rails environment settings. The `load_balancer` block configures the load balancer settings for the application.

- **`postgres.tf`**
```hcl
resource "cpln_workload" "postgres" {
  name = "postgres"
  type = "standard"
  containers = {
    postgres = {
      image = "postgres:latest"
      cpu = "500m"
      memory = "1Gi"
      envs = local.postgres_envs
      ports = [
        {
          number = 5432
          protocol = "tcp"
        }
      ]
    }
  }
  options = {
    autoscaling = {
      max_scale = 1
    }
    capacity_ai = false
  }
  firewall_spec = {
    external = {
      inbound_allow_cidr = [
        "0.0.0.0/0"
      ]
      outbound_allow_cidr = [
        "0.0.0.0/0"
      ]
    }
  }
}
```
**Description**: This file defines a workload resource for the PostgreSQL database. It specifies the container image to use, the amount of CPU and memory allocated, and the environment variables needed for the database. The `ports` section indicates that the database will listen on port 5432. The `options` block includes settings for autoscaling and capacity management. The `firewall_spec` section configures the firewall rules to allow inbound and outbound traffic.

- **`postgres_envs.tf`**
```hcl
locals {
  postgres_envs = {
    POSTGRES_USER = "user"
    POSTGRES_PASSWORD = "password"
    POSTGRES_DB = "rails_app"
  }
}
```
**Description**: This file defines local variables for the PostgreSQL environment settings. It includes the database user, password, and the name of the database that the application will connect to. These variables are referenced in the `postgres.tf` file to configure the PostgreSQL container.

- **`rails-app.tf`**
```hcl
module "rails" {
  source = "../workload"
  type = "standard"
  name = "rails"
  gvc = cpln_gvc.rails-app-staging.name
  containers = {
    rails = {
      image = "org-name/rails:latest"
      cpu = "300m"
      memory = "512Mi"
      inherit_env = true
      envs = local.rails_envs
      ports = [
        {
          number = 3000
          protocol = "http"
        }
      ]
    }
  }
  options = {
    autoscaling = {
      max_scale = 1
    }
    capacity_ai = false
  }
  firewall_spec = {
    external = {
      inbound_allow_cidr = [
        "0.0.0.0/0"
      ]
      outbound_allow_cidr = [
        "0.0.0.0/0"
      ]
    }
  }
}
```
**Description**: This file defines a module for the Rails application workload. It specifies the source of the module, the type of workload, and the name of the application. The `gvc` field links the Rails application to the previously defined GVC. The `containers` block configures the Rails container, including the image to use, CPU and memory allocation, and environment variables. The `options` block includes settings for autoscaling and capacity management, while the `firewall_spec` section configures the firewall rules.

- **`rails_envs.tf`**
```hcl
locals {
  rails_envs = {
    LOG_LEVEL = "debug"
  }
}
```
**Description**: This file defines local variables for the Rails application environment settings. It includes the log level for the application, which can be adjusted as needed. These variables are referenced in the `rails-app.tf` file to configure the Rails container.

- **`providers.tf`**
```hcl
provider "cpln" {
  org = "org-name-example"
}
```
**Description**: This file specifies the provider configuration for the Control Plane. It includes the organization name that will be used to manage resources within the Control Plane. This is essential for authenticating and authorizing access to the resources defined in the Terraform configurations.

- **`required_providers.tf`**
```hcl
terraform {
  required_providers {
    cpln = {
      source = "controlplane-com/cpln"
      version = "~> 1.0"
    }
  }
}
```
**Description**: This file defines the required providers for the Terraform configuration. It specifies the Control Plane provider, including its source and version. This ensures that Terraform knows which provider to use when managing resources.

## Application Deployment

To deploy your application, follow these steps:

1. Go to the application folder:
   ```sh
   cd terraform/rails-app-staging
   ```
2. Initialize the new Terraform working directory:
   ```sh
   terraform init
   ```
3. Generate the execution plan (what actions Terraform would take to apply the current configuration):
   ```sh
   terraform plan
   ```
4. Apply the planned changes:
   ```sh
   terraform apply
   ```

## Importing Existing Infrastructure

In addition to generating Terraform configurations, you can also import existing infrastructure into Terraform management using the `cpflow terraform import` command. This is useful when you have resources that were created outside of Terraform and you want to manage them using Terraform going forward.

### Usage

To import existing resources, run the following command:

```sh
cpflow terraform import
```

This command will import resources defined in your `controlplane.yml` and `templates` folder into the Terraform state.

## References

- [Terraform Provider Plugin](https://shakadocs.controlplane.com/terraform/installation#terraform-provider-plugin)
- [Terraform - Control Plane Examples](https://github.com/controlplane-com/examples/tree/main/terraform)
