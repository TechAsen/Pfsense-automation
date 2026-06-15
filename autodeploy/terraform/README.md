# pfSense Terraform provisioning

This Terraform code provisions one or two pfSense VMs from Proxmox templates based on:

- `autodeploy/firewall_config.yaml`
- `autodeploy/packer_config.yaml`

## Logic

For selected `pod_id`:

- If `firewall_01` exists, Terraform creates one VM.
- If `firewall_02` exists, Terraform creates a second VM.
- `firewall_01` uses `pfsense_template_01`.
- `firewall_02` uses `pfsense_template_02`.
- `hostname` becomes the Proxmox VM name.
- `pm_node` becomes the Proxmox target node.
- `vmnets` becomes the VM NIC list:
  - first item -> `net0` / pfSense `vtnet0`
  - second item -> `net1` / pfSense `vtnet1`
  - third item -> `net2` / pfSense `vtnet2`
  - etc.
- `wan_ip`, `lan_ip`, and `vhid` are intentionally not used yet.

The template VM ID is read from `packer_config.yaml`:

```yaml
pfsense_template_01:
  target_nodes:
    pve-firewall-np-02:
      vmid: 782
```

## Manual run

```bash
cd autodeploy/terraform

export VAULT_ADDR="http://vault01:8200"
export VAULT_TOKEN="<token-with-read-access>"

export TF_VAR_proxmox_token_secret="$(vault kv get -field=proxmox_token_secret NetOps/infra-nonprod)"

terraform init
terraform fmt -recursive
terraform validate

terraform plan \
  -var="location=sofia_dc" \
  -var="pod_id=np-pod02"

terraform apply \
  -var="location=sofia_dc" \
  -var="pod_id=np-pod02"
```

For a single firewall deployment:

```bash
terraform apply \
  -var="location=sofia_dc" \
  -var="pod_id=np-pre-pod"
```

## Jenkins stage example

Add this after the successful Packer template stage:

```groovy
stage('Terraform/Provision pfSense VMs') {
    when {
        expression {
            params.POD_ID != "" &&
            params.LOCATION != "" &&
            (
                env.BRANCH_NAME == 'main' ||
                env.GIT_BRANCH == 'origin/main' ||
                env.GIT_BRANCH == 'main'
            )
        }
    }

    steps {
        withCredentials([
            [
                $class: 'VaultTokenCredentialBinding',
                credentialsId: "${vaultAppRoleCredsId}",
                vaultAddr: "${vaultAddr}",
                addrVariable: 'VAULT_ADDR',
                tokenVariable: 'VAULT_TOKEN'
            ]
        ]) {
            dir("autodeploy/terraform") {
                withEnv([
                    "TF_VAR_location=${params.LOCATION}",
                    "TF_VAR_pod_id=${params.POD_ID}"
                ]) {
                    sh """
                        set -eu

                        if [ -z "${VAULT_TOKEN:-}" ]; then
                            echo "ERROR: VAULT_TOKEN is not exported."
                            exit 1
                        fi

                        export TF_VAR_proxmox_token_secret="$(vault kv get -field=proxmox_token_secret NetOps/infra-nonprod)"

                        terraform init
                        terraform fmt -check -recursive
                        terraform validate
                        terraform plan -out=tfplan
                        terraform apply -auto-approve tfplan
                    """
                }
            }
        }
    }
}
```

## Notes

The bpg/proxmox provider expects the API token in the format:

```text
user@realm!tokenid=token-secret
```

The code builds that from:

- `packer_config.yaml` `user`, for example `root@pam!pve-np-terraform`
- Vault secret `proxmox_token_secret`
