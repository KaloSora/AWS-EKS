# Infrastructure entry script

From the repository root:

```sh
./script/run_infra_create.sh
```

The script uses bash, sources `run_aws_auth.sh` from its own directory, then runs
`terraform init -backend-config="dev.s3.tfbackend"` and `terraform validate` in
the repository's `modules` directory. Paths are resolved from the script, so it
can also be invoked by absolute path from another working directory.

Any authentication, initialization or validation failure stops execution.
Despite the filename, the current script only initializes and validates; it
does not run `terraform apply` or create an EKS cluster. Existing authentication
requirements and configuration in `run_aws_auth.sh` still apply.
