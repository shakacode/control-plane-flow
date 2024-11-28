# Terraform

## Overview

The Terraform feature in this project allows you to manage your Control Plane (CPLN) configurations using Terraform by:
1. Generating Terraform configuration files from existing CPLN YAML configuration files
2. Easily importing existing infrastructure into Terraform management

You can continue working with CPLN configuration files in YAML format and start using Terraform at any time.

## Benefits of Using Terraform Over YAML Configs

1. **State Management**: Terraform maintains a state file that tracks the current state of your infrastructure, making it easier to manage changes and updates.
2. **Dependency Management**: Terraform automatically handles dependencies between resources, ensuring that they are created or destroyed in the correct order.
3. **Multi-Cloud Support**: With Terraform, you can manage resources across multiple cloud providers seamlessly, allowing for a more flexible architecture.
4. **Plan and Apply**: Terraform provides a clear plan of what changes will be made before applying them, reducing the risk of unintended modifications.

## Usage

Let's take a look at how to deploy a [simple Rails application](example/.controlplane/controlplane.yml) on CPLN using Terraform:

```
.controlplane/
├── templates/
│   ├── app.yml -- GVC config
│   ├── postgres.yml -- Workload config for PostgreSQL
│   └── rails.yml -- Workload config for Rails
└── controlplane.yml -- Configs for overall application
```

### Generating Terraform configurations

To generate Terraform configurations, run the following command from the project root:

```sh
cpflow terraform generate
```

Invoking this command will generate a new `terraform` folder with subfolders containing Terraform configurations for each application described in `controlplane.yml`:

```
terraform/
├── rails-app-production/ -- Terraform configurations for production environment
│   ├── gvc.tf -- GVC config in HCL
│   ├── identities.tf -- Identities config in HCL
│   ├── postgres.tf -- Postgres workload config in HCL
│   ├── postgres_envs.tf -- ENV variables for Postgres workload in HCL
│   ├── providers.tf -- Providers config in HCL
│   ├── rails.tf -- Rails workload config in HCL
│   ├── rails_envs.tf -- ENV variables for Rails workload in HCL
│   ├── required_providers.tf -- Required providers config in HCL
│   └── secrets.tf -- Secrets config in HCL
├── rails-app-staging/ -- Terraform configurations for staging environment
│   ├── gvc.tf -- GVC config in HCL
│   ├── identities.tf -- Identities config in HCL
│   ├── postgres.tf -- Postgres workload config in HCL
│   ├── postgres_envs.tf -- ENV variables for Postgres workload in HCL
│   ├── providers.tf -- Providers config in HCL
│   ├── rails.tf -- Rails workload config in HCL
│   ├── rails_envs.tf -- ENV variables for Rails workload in HCL
│   ├── required_providers.tf -- Required providers config in HCL
│   └── secrets.tf -- Secrets config in HCL
├── workload/ -- Terraform configurations for workload module
│   ├── main.tf -- Main config for workload resource in HCL
│   ├── required_providers.tf -- Required providers for Terraform in HCL
│   └── variables.tf -- Variables used to create config for workload resource in HCL
```

### Importing existing infrastructure

Now we need to import existing infrastructure into Terraform management because some resources can already exist on CPLN and Terraform needs to know about this:

```sh
cpflow terraform import
```

This command will initialize Terraform and import resources defined in your `controlplane.yml` and `templates` folder into the Terraform state for each application.

Please note that during the import process, you may encounter errors indicating that non-existing resources are being imported. This is expected behavior and can be safely ignored.

### Application deployment using Terraform

Preparations are complete, and now we can use Terraform commands directly to deploy our application.

1. **Navigate to the Application Folder**:
   ```sh
   cd terraform/rails-app-staging
   ```

2. **Plan the Deployment**:
   ```sh
   terraform plan
   ```

3. **Apply the Configuration**:
   ```sh
   terraform apply
   ```

You can visit [Details](details.md) to learn more about how CPLN templates in YAML format are transformed to Terraform configurations.

## References

- [Terraform Provider Plugin](https://shakadocs.controlplane.com/terraform/installation#terraform-provider-plugin)
- [Terraform - Control Plane Examples](https://github.com/controlplane-com/examples/tree/main/terraform)
