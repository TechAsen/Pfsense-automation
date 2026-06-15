def bitbucketUrl = 'gitlab.techasen.eu'
def vaultAppRoleCredsId = 'vault-approle-jfrog-terraform-pipeline'
def vaultAddr = 'http://vault.techasen.eu:8200'

def podList = ['np-mgmt', 'np-pod01', 'np-pod02', 'np-pod03', 'np-pre-pod']

def allowedApprovers = ['asen.n.asenov']

pipeline {
    agent any

    parameters {
        choice(
            name: 'LOCATION',
            choices: ['sofia_dc'],
            description: 'Choose between SOFIA or HR point of deployment'
        )

        choice(
            name: 'POD_ID',
            choices: podList,
            description: 'Select the Environment'
        )

        string(
            name: 'REQUIRED_APPROVALS',
            defaultValue: '1',
            description: 'Number of required approvals before template build'
        )

        booleanParam(
            name: 'REBUILD_TEMPLATES',
            defaultValue: false,
            description: 'If true, existing Proxmox pfSense templates will be deleted and rebuilt by Packer'
        )
    }

    stages {
        stage('Debug') {
            steps {
                sh '''
                    set +e
                    echo "WORKSPACE=$WORKSPACE"
                    echo "JOB_NAME=$JOB_NAME"
                    echo "BRANCH_NAME=$BRANCH_NAME"
                    echo "GIT_BRANCH=$GIT_BRANCH"
                    echo "Running on host:"
                    hostname
                    whoami
                    git --version
                    packer version
                    terraform version
                    vault version
                    curl --version | head -n 1
                    python3 --version
                    java -version
                '''

                echo "LOCATION=${params.LOCATION}"
                echo "POD_ID=${params.POD_ID}"
            }
        }

        stage('Approval') {
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
                script {
                    int requiredApprovals = params.REQUIRED_APPROVALS as Integer
                    if (requiredApprovals < 1) {
                        error "REQUIRED_APPROVALS must be at least 1"
                    }

                    if (requiredApprovals > allowedApprovers.size()) {
                        error "REQUIRED_APPROVALS=${requiredApprovals} is greater than allowed approvers count=${allowedApprovers.size()}"
                    }

                    def approvedBy = [] as Set

                    timeout(time: 30, unit: 'MINUTES') {
                        while (approvedBy.size() < requiredApprovals) {
                            def approval = input(
                                id: "pfsense-template-approval-${approvedBy.size() + 1}",
                                message: "Approve pfSense pipeline for LOCATION=${params.LOCATION}, POD_ID=${params.POD_ID}, REBUILD_TEMPLATES=${params.REBUILD_TEMPLATES}?",
                                ok: 'Approve',
                                submitter: allowedApprovers.join(','),
                                submitterParameter: 'APPROVER'
                            )

                            def approver = approval instanceof Map ? approval['APPROVER'] : approval

                            if (!approver) {
                                error "Could not detect approver"
                            }

                            if (approvedBy.contains(approver)) {
                                echo "${approver} already approved. Waiting for another approver."
                            } else {
                                approvedBy.add(approver)
                                echo "Approval ${approvedBy.size()}/${requiredApprovals} received from ${approver}"
                            }
                        }
                    }
                }
            }
        }

        stage('Packer/Build templates') {
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

            parallel {
                stage('Template 1') {
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
                            dir("autodeploy/packer") {
                                script {
                                    def packerConfig = readYaml file: '../packer_config.yaml'
                                    def firewallConfig = readYaml file: '../firewall_config.yaml'

                                    def locationData = packerConfig?.packer?.get(params.LOCATION)
                                    if (!locationData) {
                                        error "Missing packer configuration for LOCATION=${params.LOCATION}"
                                    }

                                    def podData = firewallConfig?.get(params.POD_ID)
                                    if (!podData) {
                                        error "Missing firewall configuration for POD_ID=${params.POD_ID}"
                                    }

                                    def vaultData = firewallConfig?.common_args?.vault
                                    if (!vaultData?.vault_addr) {
                                        error "Missing common_args.vault.vault_addr in firewall_config.yaml"
                                    }

                                    def vaultInfraPath = vaultData?.secret_paths?.infra ?: 'NetOps/infra-nonprod'

                                    def nodeKey = podData?.firewall_01?.pm_node
                                    if (!nodeKey) {
                                        error "Missing ${params.POD_ID}.firewall_01.pm_node in firewall_config.yaml"
                                    }

                                    def targetNodeData = locationData?.pfsense_template_01?.target_nodes?.get(nodeKey)
                                    if (!targetNodeData) {
                                        error "Template pfsense_template_01 has no target_nodes entry for ${nodeKey}"
                                    }

                                    def templateVmid = targetNodeData?.vmid
                                    if (!templateVmid) {
                                        error "Missing pfsense_template_01.target_nodes.${nodeKey}.vmid in packer_config.yaml"
                                    }

                                    writeJSON file: 'packer_config.json', json: locationData

                                    withEnv([
                                        "VAULT_ADDR=${vaultData.vault_addr}",
                                        "VAULT_INFRA_SECRET_PATH=${vaultInfraPath}",
                                        "PROXMOX_URL=${locationData.url}",
                                        "PROXMOX_USER=${locationData.user}",
                                        "NODE_KEY=${nodeKey}",
                                        "TEMPLATE_KEY=pfsense_template_01",
                                        "TEMPLATE_NAME=${locationData.pfsense_template_01.name}",
                                        "TEMPLATE_VMID=${templateVmid}",
                                        "REBUILD_TEMPLATES=${params.REBUILD_TEMPLATES}"
                                    ]) {
                                        sh '''
                                            set +x
                                            set -eu

                                            echo "Vault address: ${VAULT_ADDR}"
                                            echo "Template key: ${TEMPLATE_KEY}"
                                            echo "Template name: ${TEMPLATE_NAME}"
                                            echo "Template VMID: ${TEMPLATE_VMID}"
                                            echo "Node key: ${NODE_KEY}"

                                            if [ -z "${VAULT_TOKEN:-}" ]; then
                                                echo "ERROR: VAULT_TOKEN is not exported. Check Jenkins VaultTokenCredentialBinding credential."
                                                exit 1
                                            fi

                                            PROXMOX_TOKEN_SECRET="$(vault kv get -field=proxmox_token_secret "${VAULT_INFRA_SECRET_PATH}")"
                                            PROXMOX_BASE_URL="${PROXMOX_URL%/api2/json}"
                                            PROXMOX_API_URL="${PROXMOX_BASE_URL}/api2/json"
                                            CHECK_FILE=".template-check-${TEMPLATE_KEY}-${NODE_KEY}-${TEMPLATE_VMID}.json"
                                            TEMPLATE_CHECK_URL="${PROXMOX_API_URL}/nodes/${NODE_KEY}/qemu/${TEMPLATE_VMID}/config"

                                            echo "Checking Proxmox template existence: ${NODE_KEY}/${TEMPLATE_VMID}"

                                            http_code="$(curl -sk -o "${CHECK_FILE}" -w "%{http_code}" \
                                                -H "Authorization: PVEAPIToken=${PROXMOX_USER}=${PROXMOX_TOKEN_SECRET}" \
                                                "${TEMPLATE_CHECK_URL}" || true)"

                                            template_missing="false"

                                            if [ "${http_code}" = "200" ]; then
                                                if grep -Eq '"template"[[:space:]]*:[[:space:]]*1' "${CHECK_FILE}"; then
                                                    if [ "${REBUILD_TEMPLATES}" != "true" ]; then
                                                        echo "Template ${TEMPLATE_NAME} VMID=${TEMPLATE_VMID} already exists on ${NODE_KEY}. Skipping Packer build."
                                                        exit 0
                                                    fi

                                                    echo "REBUILD_TEMPLATES=true. Deleting existing template ${TEMPLATE_NAME} VMID=${TEMPLATE_VMID} on ${NODE_KEY}."
                                                    DELETE_FILE=".template-delete-${TEMPLATE_KEY}-${NODE_KEY}-${TEMPLATE_VMID}.json"
                                                    delete_code="$(curl -sk -X DELETE -o "${DELETE_FILE}" -w "%{http_code}" \
                                                        -H "Authorization: PVEAPIToken=${PROXMOX_USER}=${PROXMOX_TOKEN_SECRET}" \
                                                        --data-urlencode "purge=1" \
                                                        --data-urlencode "destroy-unreferenced-disks=1" \
                                                        "${PROXMOX_API_URL}/nodes/${NODE_KEY}/qemu/${TEMPLATE_VMID}" || true)"

                                                    if [ "${delete_code}" != "200" ]; then
                                                        echo "ERROR: Failed to delete existing template. HTTP=${delete_code}"
                                                        cat "${DELETE_FILE}" || true
                                                        exit 1
                                                    fi

                                                    echo "Waiting for Proxmox template VMID=${TEMPLATE_VMID} to disappear..."
                                                    for i in $(seq 1 60); do
                                                        WAIT_FILE=".template-wait-${TEMPLATE_KEY}-${NODE_KEY}-${TEMPLATE_VMID}.json"
                                                        wait_code="$(curl -sk -o "${WAIT_FILE}" -w "%{http_code}" \
                                                            -H "Authorization: PVEAPIToken=${PROXMOX_USER}=${PROXMOX_TOKEN_SECRET}" \
                                                            "${TEMPLATE_CHECK_URL}" || true)"

                                                        if [ "${wait_code}" = "404" ] || { [ "${wait_code}" = "500" ] && grep -qi "does not exist" "${WAIT_FILE}"; }; then
                                                            echo "Existing template deleted."
                                                            break
                                                        fi

                                                        if [ "${i}" = "60" ]; then
                                                            echo "ERROR: Template VMID=${TEMPLATE_VMID} still exists after waiting. Last HTTP=${wait_code}"
                                                            cat "${WAIT_FILE}" || true
                                                            exit 1
                                                        fi

                                                        sleep 5
                                                    done
                                                else
                                                    echo "ERROR: VMID=${TEMPLATE_VMID} exists on ${NODE_KEY}, but it is not marked as a Proxmox template."
                                                    cat "${CHECK_FILE}" || true
                                                    exit 1
                                                fi
                                            elif [ "${http_code}" = "404" ]; then
                                                template_missing="true"
                                            elif [ "${http_code}" = "500" ] && grep -qi "does not exist" "${CHECK_FILE}"; then
                                                echo "Proxmox returned HTTP=500, but response says VMID=${TEMPLATE_VMID} does not exist. Treating as missing template."
                                                template_missing="true"
                                            else
                                                echo "ERROR: Unexpected Proxmox API response while checking template. HTTP=${http_code}"
                                                cat "${CHECK_FILE}" || true
                                                exit 1
                                            fi

                                            echo "Template ${TEMPLATE_NAME} VMID=${TEMPLATE_VMID} is absent or was removed. Building with Packer."

                                            packer init .

                                            packer validate \
                                                -var="template_key=${TEMPLATE_KEY}" \
                                                -var="node_key=${NODE_KEY}" \
                                                .

                                            packer build -on-error=ask \
                                                -var="template_key=${TEMPLATE_KEY}" \
                                                -var="node_key=${NODE_KEY}" \
                                                .
                                        '''
                                    }
                                }
                            }
                        }
                    }
                }

                stage('Template 2') {
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
                            dir("autodeploy/packer") {
                                script {
                                    def packerConfig = readYaml file: '../packer_config.yaml'
                                    def firewallConfig = readYaml file: '../firewall_config.yaml'

                                    def locationData = packerConfig?.packer?.get(params.LOCATION)
                                    if (!locationData) {
                                        error "Missing packer configuration for LOCATION=${params.LOCATION}"
                                    }

                                    def podData = firewallConfig?.get(params.POD_ID)
                                    if (!podData) {
                                        error "Missing firewall configuration for POD_ID=${params.POD_ID}"
                                    }

                                    if (!podData?.firewall_02) {
                                        echo "POD_ID=${params.POD_ID} has no firewall_02. Skipping pfsense_template_02."
                                        return
                                    }

                                    def vaultData = firewallConfig?.common_args?.vault
                                    if (!vaultData?.vault_addr) {
                                        error "Missing common_args.vault.vault_addr in firewall_config.yaml"
                                    }

                                    def vaultInfraPath = vaultData?.secret_paths?.infra ?: 'NetOps/infra-nonprod'

                                    def nodeKey = podData?.firewall_02?.pm_node
                                    if (!nodeKey) {
                                        error "Missing ${params.POD_ID}.firewall_02.pm_node in firewall_config.yaml"
                                    }

                                    def targetNodeData = locationData?.pfsense_template_02?.target_nodes?.get(nodeKey)
                                    if (!targetNodeData) {
                                        error "Template pfsense_template_02 has no target_nodes entry for ${nodeKey}"
                                    }

                                    def templateVmid = targetNodeData?.vmid
                                    if (!templateVmid) {
                                        error "Missing pfsense_template_02.target_nodes.${nodeKey}.vmid in packer_config.yaml"
                                    }

                                    writeJSON file: 'packer_config.json', json: locationData

                                    withEnv([
                                        "VAULT_ADDR=${vaultData.vault_addr}",
                                        "VAULT_INFRA_SECRET_PATH=${vaultInfraPath}",
                                        "PROXMOX_URL=${locationData.url}",
                                        "PROXMOX_USER=${locationData.user}",
                                        "NODE_KEY=${nodeKey}",
                                        "TEMPLATE_KEY=pfsense_template_02",
                                        "TEMPLATE_NAME=${locationData.pfsense_template_02.name}",
                                        "TEMPLATE_VMID=${templateVmid}",
                                        "REBUILD_TEMPLATES=${params.REBUILD_TEMPLATES}"
                                    ]) {
                                        sh '''
                                            set +x
                                            set -eu

                                            echo "Vault address: ${VAULT_ADDR}"
                                            echo "Template key: ${TEMPLATE_KEY}"
                                            echo "Template name: ${TEMPLATE_NAME}"
                                            echo "Template VMID: ${TEMPLATE_VMID}"
                                            echo "Node key: ${NODE_KEY}"

                                            if [ -z "${VAULT_TOKEN:-}" ]; then
                                                echo "ERROR: VAULT_TOKEN is not exported. Check Jenkins VaultTokenCredentialBinding credential."
                                                exit 1
                                            fi

                                            PROXMOX_TOKEN_SECRET="$(vault kv get -field=proxmox_token_secret "${VAULT_INFRA_SECRET_PATH}")"
                                            PROXMOX_BASE_URL="${PROXMOX_URL%/api2/json}"
                                            PROXMOX_API_URL="${PROXMOX_BASE_URL}/api2/json"
                                            CHECK_FILE=".template-check-${TEMPLATE_KEY}-${NODE_KEY}-${TEMPLATE_VMID}.json"
                                            TEMPLATE_CHECK_URL="${PROXMOX_API_URL}/nodes/${NODE_KEY}/qemu/${TEMPLATE_VMID}/config"

                                            echo "Checking Proxmox template existence: ${NODE_KEY}/${TEMPLATE_VMID}"

                                            http_code="$(curl -sk -o "${CHECK_FILE}" -w "%{http_code}" \
                                                -H "Authorization: PVEAPIToken=${PROXMOX_USER}=${PROXMOX_TOKEN_SECRET}" \
                                                "${TEMPLATE_CHECK_URL}" || true)"

                                            template_missing="false"

                                            if [ "${http_code}" = "200" ]; then
                                                if grep -Eq '"template"[[:space:]]*:[[:space:]]*1' "${CHECK_FILE}"; then
                                                    if [ "${REBUILD_TEMPLATES}" != "true" ]; then
                                                        echo "Template ${TEMPLATE_NAME} VMID=${TEMPLATE_VMID} already exists on ${NODE_KEY}. Skipping Packer build."
                                                        exit 0
                                                    fi

                                                    echo "REBUILD_TEMPLATES=true. Deleting existing template ${TEMPLATE_NAME} VMID=${TEMPLATE_VMID} on ${NODE_KEY}."
                                                    DELETE_FILE=".template-delete-${TEMPLATE_KEY}-${NODE_KEY}-${TEMPLATE_VMID}.json"
                                                    delete_code="$(curl -sk -X DELETE -o "${DELETE_FILE}" -w "%{http_code}" \
                                                        -H "Authorization: PVEAPIToken=${PROXMOX_USER}=${PROXMOX_TOKEN_SECRET}" \
                                                        --data-urlencode "purge=1" \
                                                        --data-urlencode "destroy-unreferenced-disks=1" \
                                                        "${PROXMOX_API_URL}/nodes/${NODE_KEY}/qemu/${TEMPLATE_VMID}" || true)"

                                                    if [ "${delete_code}" != "200" ]; then
                                                        echo "ERROR: Failed to delete existing template. HTTP=${delete_code}"
                                                        cat "${DELETE_FILE}" || true
                                                        exit 1
                                                    fi

                                                    echo "Waiting for Proxmox template VMID=${TEMPLATE_VMID} to disappear..."
                                                    for i in $(seq 1 60); do
                                                        WAIT_FILE=".template-wait-${TEMPLATE_KEY}-${NODE_KEY}-${TEMPLATE_VMID}.json"
                                                        wait_code="$(curl -sk -o "${WAIT_FILE}" -w "%{http_code}" \
                                                            -H "Authorization: PVEAPIToken=${PROXMOX_USER}=${PROXMOX_TOKEN_SECRET}" \
                                                            "${TEMPLATE_CHECK_URL}" || true)"

                                                        if [ "${wait_code}" = "404" ] || { [ "${wait_code}" = "500" ] && grep -qi "does not exist" "${WAIT_FILE}"; }; then
                                                            echo "Existing template deleted."
                                                            break
                                                        fi

                                                        if [ "${i}" = "60" ]; then
                                                            echo "ERROR: Template VMID=${TEMPLATE_VMID} still exists after waiting. Last HTTP=${wait_code}"
                                                            cat "${WAIT_FILE}" || true
                                                            exit 1
                                                        fi

                                                        sleep 5
                                                    done
                                                else
                                                    echo "ERROR: VMID=${TEMPLATE_VMID} exists on ${NODE_KEY}, but it is not marked as a Proxmox template."
                                                    cat "${CHECK_FILE}" || true
                                                    exit 1
                                                fi
                                            elif [ "${http_code}" = "404" ]; then
                                                template_missing="true"
                                            elif [ "${http_code}" = "500" ] && grep -qi "does not exist" "${CHECK_FILE}"; then
                                                echo "Proxmox returned HTTP=500, but response says VMID=${TEMPLATE_VMID} does not exist. Treating as missing template."
                                                template_missing="true"
                                            else
                                                echo "ERROR: Unexpected Proxmox API response while checking template. HTTP=${http_code}"
                                                cat "${CHECK_FILE}" || true
                                                exit 1
                                            fi

                                            echo "Template ${TEMPLATE_NAME} VMID=${TEMPLATE_VMID} is absent or was removed. Building with Packer."

                                            packer init .

                                            packer validate \
                                                -var="template_key=${TEMPLATE_KEY}" \
                                                -var="node_key=${NODE_KEY}" \
                                                .

                                            packer build -on-error=ask \
                                                -var="template_key=${TEMPLATE_KEY}" \
                                                -var="node_key=${NODE_KEY}" \
                                                .
                                        '''
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

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
                        script {
                            def firewallConfig = readYaml file: '../firewall_config.yaml'
                            def packerConfig = readYaml file: '../packer_config.yaml'

                            def podData = firewallConfig?.get(params.POD_ID)
                            if (!podData) {
                                error "Missing firewall configuration for POD_ID=${params.POD_ID}"
                            }

                            def locationData = packerConfig?.packer?.get(params.LOCATION)
                            if (!locationData) {
                                error "Missing packer configuration for LOCATION=${params.LOCATION}"
                            }

                            def vaultData = firewallConfig?.common_args?.vault
                            if (!vaultData?.vault_addr) {
                                error "Missing common_args.vault.vault_addr in firewall_config.yaml"
                            }

                            def vaultInfraPath = vaultData?.secret_paths?.infra ?: 'NetOps/infra-nonprod'

                            def fw1Node = podData?.firewall_01?.pm_node
                            if (!fw1Node) {
                                error "Missing ${params.POD_ID}.firewall_01.pm_node in firewall_config.yaml"
                            }

                            if (!locationData?.pfsense_template_01?.target_nodes?.get(fw1Node)) {
                                error "Terraform precheck failed: pfsense_template_01 has no target_nodes entry for ${fw1Node}"
                            }

                            if (podData?.firewall_02) {
                                def fw2Node = podData?.firewall_02?.pm_node
                                if (!fw2Node) {
                                    error "Missing ${params.POD_ID}.firewall_02.pm_node in firewall_config.yaml"
                                }

                                if (!locationData?.pfsense_template_02?.target_nodes?.get(fw2Node)) {
                                    error "Terraform precheck failed: pfsense_template_02 has no target_nodes entry for ${fw2Node}"
                                }
                            } else {
                                echo "POD_ID=${params.POD_ID} has no firewall_02. Terraform will provision only firewall_01."
                            }

                            withEnv([
                                "VAULT_ADDR=${vaultData.vault_addr}",
                                "VAULT_INFRA_SECRET_PATH=${vaultInfraPath}",
                                "TF_VAR_location=${params.LOCATION}",
                                "TF_VAR_pod_id=${params.POD_ID}"
                            ]) {
                                sh '''
                                    set +x
                                    set -eu

                                    echo "Terraform location: ${TF_VAR_location}"
                                    echo "Terraform POD_ID: ${TF_VAR_pod_id}"
                                    echo "Vault address: ${VAULT_ADDR}"

                                    if [ -z "${VAULT_TOKEN:-}" ]; then
                                        echo "ERROR: VAULT_TOKEN is not exported. Check Jenkins VaultTokenCredentialBinding credential."
                                        exit 1
                                    fi

                                    export TF_VAR_proxmox_token_secret="$(vault kv get -field=proxmox_token_secret "${VAULT_INFRA_SECRET_PATH}")"

                                    terraform init -input=false
                                    terraform fmt -recursive
                                    terraform validate

                                    terraform plan \
                                        -input=false \
                                        -out=tfplan

                                    terraform apply \
                                        -input=false \
                                        -auto-approve \
                                        tfplan
                                '''
                            }
                        }
                    }
                }
            }
        }
    }
}
