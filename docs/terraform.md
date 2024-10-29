# Terraform

You can manage your CPLN configuration through `cpflow` commands and later invoke the generation of Terraform configuration files by running:

```sh
cpflow terraform generate
```

This command will create Terraform configurations for each application defined in `controlplane.yml`, utilizing templates from the `templates` folder.

Each time this command is invoked, Terraform configurations will be recreated. You can continue working with CPLN configuration files in YAML format and simply transform them to Terraform format anytime.
