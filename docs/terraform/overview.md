# Terraform

### Overview

You can manage your Control Plane (CPLN) configuration through `cpflow` commands and later invoke the generation of Terraform configuration files by running:

```sh
cpflow terraform generate
```

This command will create Terraform configurations for each application defined in `controlplane.yml`, utilizing templates from the `templates` folder.

Each time this command is invoked, Terraform configurations will be recreated, and the Terraform lock file will be preserved.

You can continue working with CPLN configuration files in YAML format and simply transform them to Terraform format at any time.

### Benefits of Using Terraform Over YAML Configs

1. **State Management**: Terraform maintains a state file that tracks the current state of your infrastructure, making it easier to manage changes and updates.
2. **Dependency Management**: Terraform automatically handles dependencies between resources, ensuring that they are created or destroyed in the correct order.
3. **Multi-Cloud Support**: With Terraform, you can manage resources across multiple cloud providers seamlessly, allowing for a more flexible architecture.
4. **Plan and Apply**: Terraform provides a clear plan of what changes will be made before applying them, reducing the risk of unintended modifications.

### Usage

Suppose that you have CPLN configurations in YAML format for a Rails application with the following project structure (see the `example` folder):

```
.controlplane/
├── templates/
│   ├── app.yml -- GVC config
│   ├── postgres.yml -- Workload config for PostgreSQL
│   └── rails.yml -- Workload config for Rails
├── controlplane.yml -- Configs for overall application
```

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

### References

- [Terraform Provider Plugin](https://shakadocs.controlplane.com/terraform/installation#terraform-provider-plugin)
- [Terraform - Control Plane Examples](https://github.com/controlplane-com/examples/tree/main/terraform)
