# Terraform backend initialization

Run from this directory with valid AWS credentials exported in the terminal:

```sh
terraform init -backend-config="dev.s3.tfbackend"
terraform plan -var-file="dev.tfvars"
```

`provider.tf` declares the S3 backend, state key and encryption setting.
`dev.s3.tfbackend` supplies the bucket and backend region during initialization.
The default workspace uses
`s3://terraform-state-823058656952/eks/dev/terraform.tfstate`.
The bucket must already exist.

Backend blocks cannot reference input variables (`var.*`), locals or data
sources. `dev.tfvars` supplies project input variables during plan/apply; it
does not supply backend settings. Existing variable declarations and tfvars
values are retained, but currently are not referenced by the backend. When an
AWS provider is added, it can use `region = var.aws_region` independently of
the backend's region.

Passing `-var-file` to `terraform init` does not make input variables available
to the backend. Use `-backend-config` for backend settings.

If existing state must be moved to this backend, back it up first and use
`terraform init -migrate-state -backend-config="dev.s3.tfbackend"` after reviewing
the source and destination. `-reconfigure` does not migrate state.

Supply credentials through the environment; keep credentials out of backend
configuration. Exclude `.terraform/`, state and saved plan files from Git.

References:
- https://developer.hashicorp.com/terraform/language/backend#partial-configuration
- https://developer.hashicorp.com/terraform/cli/commands/init
