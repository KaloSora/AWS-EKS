# EC2 NAT Instance Module

Provides outbound IPv4 connectivity for private EKS nodes through one shared EC2 instance. The default is an on-demand `t4g.micro` running Amazon Linux 2023 ARM64, with an encrypted 8 GiB gp3 root volume and an Elastic IP. x86_64 instance types select the corresponding AL2023 image automatically.

```text
Private EKS nodes -> private default routes -> NAT ENI/EC2 -> Internet Gateway
                   -> S3 Gateway endpoint for regional S3 traffic
```

## Resources and Security

- A dedicated ENI in a public subnet, with source/destination checks disabled.
- An Elastic IP associated before instance boot. The public subnet does not need automatic public IP assignment.
- An EC2 instance with IMDSv2 required, no SSH key, and no inbound SSH rule.
- Security group rules allowing private-subnet clients to reach TCP 80/443 by default. Customize `allowed_tcp_ports` for additional TCP services. UDP and ICMP forwarding are not enabled by these rules. VPC DNS remains available directly through the VPC resolver.
- Persistent IP forwarding and source-restricted iptables masquerading, configured by cloud-init. Rules are saved for reboot persistence. AL2023 installs `iptables-services` from the AWS repository with retries.
- An IAM instance profile with `AmazonSSMManagedInstanceCore`, for SSM management over outbound HTTPS. It grants no EKS or workload permissions. Operator SSM access requires separate IAM permissions.
- One default route per supplied private route table, pointing at the NAT ENI. Existing S3 Gateway routes continue to take precedence for regional S3 traffic.

The caller must ensure the public subnet has a working Internet Gateway route before the instance boots. The root module uses `depends_on = [module.vpc]` to include the public route and associations. Do not manage the same private default routes elsewhere.

## Root Configuration

`modules/ec2_nat_instance.tf` places NAT in the first configured public subnet and connects every private route table. EKS nodes remain private. `modules/eks.tf` depends on both NAT and the retained S3 Gateway endpoint.

Configure the instance in `modules/dev.tfvars`:

```hcl
nat_instance_type = "t4g.micro"
# Optional: pin an AL2023 AMI that matches the chosen architecture.
# nat_instance_ami_id = "ami-..."

# NAT handles AWS public APIs; avoid recreating paid Interface endpoints.
vpc_endpoint_interface_services = []
```

When `nat_instance_ami_id` is null, the module resolves the current AWS public SSM AMI parameter. A later AMI update can cause instance replacement; pin the AMI for controlled upgrades. User-data changes also replace the instance. The ENI and Elastic IP remain stable when only the instance is replaced, but NAT traffic is interrupted during replacement. Burstable instances use standard CPU credits to avoid surplus-credit charges; throughput can fall when credits run out.

## Bootstrap and Verification

From the project root:

```bash
terraform -chdir=modules init -backend-config="dev.s3.tfbackend"
terraform -chdir=modules validate
terraform -chdir=modules plan -var-file="dev.tfvars" -target=module.ec2_nat_instance
terraform -chdir=modules apply -var-file="dev.tfvars" -target=module.ec2_nat_instance
```

Review and approve the plan before applying. Targeting NAT first creates its VPC dependencies without creating EKS or deleting existing Interface endpoints. AWS instance creation completion does not wait for cloud-init. Before starting EKS, use SSM Session Manager to check the instance:

```bash
NAT_INSTANCE_ID="$(terraform -chdir=modules output -raw nat_instance_id)"
aws ssm start-session --region ap-southeast-1 --target "$NAT_INSTANCE_ID"
```

Session Manager requires the AWS CLI Session Manager plugin. Allow time for the agent to register. Inside the NAT instance:

```bash
sudo cloud-init status --wait
sudo test -f /var/lib/nat-instance/ready
sudo sysctl net.ipv4.ip_forward
sudo iptables -t nat -S POSTROUTING
sudo iptables -S FORWARD
curl -I https://sts.ap-southeast-1.amazonaws.com
```

The marker is created only after NAT rules and services are configured. An HTTP response from STS proves connectivity even if the unauthenticated request is rejected. After NAT is ready:

```bash
terraform -chdir=modules plan -var-file="dev.tfvars"
terraform -chdir=modules apply -var-file="dev.tfvars"
```

A full apply includes every root resource, including budget, VPC, S3 endpoint, NAT, and EKS. The existing EKS creation script also includes NAT through the EKS dependency. For an existing cluster or a fast retry, verify NAT readiness explicitly before using the script. EKS uses HTTP/HTTPS egress for AWS APIs and image registries; endpoint connectivity does not replace IAM permissions.

Verify an actual HTTPS request from a private node or Pod after deployment, along with `kubectl get nodes` and `kubectl get pods -n kube-system`. NAT-local checks alone do not prove private-subnet forwarding works. On bootstrap failure, inspect `/var/log/cloud-init-output.log` through SSM. This implementation does not automatically wait for cloud-init, repair unhealthy NAT instances, or fail over routes.

## Replacing or Removing Interface Endpoints

The development configuration sets `vpc_endpoint_interface_services = []`. If Interface endpoints still exist in Terraform state, the next full plan will refresh their status. Endpoints already deleted through AWS will not be recreated by this configuration. Do not manually edit state to handle those deletions.

If endpoints still exist in AWS, bootstrap and verify NAT first, then review the full plan that removes them. The root configuration retains the S3 Gateway endpoint, which has no additional endpoint charge; if it was deleted manually, Terraform will propose recreating it. The endpoint module may retain its unused security group and subnet rules when the Interface service set is empty; those resources have no endpoint hourly charge.

## Cost and Availability

Charges include EC2 instance hours, EBS storage, the public IPv4 address, and applicable data transfer. There is no NAT Gateway processing fee. A single instance is a single point of failure, and clients in other AZs can incur cross-AZ data transfer charges. Size the instance for the expected traffic, monitor instance health, and maintain OS updates. This design is intended for small development environments; production deployments generally need a resilient egress design.

References: [AWS NAT instance guide](https://docs.aws.amazon.com/vpc/latest/userguide/work-with-nat-instances.html), [AL2023 package management](https://docs.aws.amazon.com/linux/al2023/ug/package-management.html).
