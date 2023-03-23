# Vault-Deployment-tutorial
Capture lessons learnt &amp; automate Vault deployment in Minikube with production hardening practices 

## References :
1. Vault raft : https://developer.hashicorp.com/vault/tutorials/kubernetes/kubernetes-minikube-raft
2. Distribute Credentials Securely Using Secrets : https://kubernetes.io/docs/tasks/inject-data-application/distribute-credentials-secure/ 
3. App role in production : https://stackoverflow.com/questions/57592189/how-to-use-hashicorp-vaults-approle-in-production
4. TLS enabled : https://developer.hashicorp.com/vault/tutorials/kubernetes/kubernetes-minikube-tls
5. Leveraging k8s service account with k8s auth & approle auth : https://medium.com/ww-engineering/working-with-vault-secrets-on-kubernetes-fde381137d88
6. https://cogarius.medium.com/a-vault-for-all-your-secrets-full-tls-on-kubernetes-with-kv-v2-c0ecd42853e1

## Deploying vault :
1. Start minikube : `minikube start --memory 6144 --cpus 3`
2. Start kube proxy against API server (in different terminal): `kubectl proxy --port=16178`
3. Deploying vault :
   1. Setting required params:
     ```
     // Let local system talk to k8s cluster via proxy
     export KUBE_ADDR=127.0.0.1:16178
     
     // Create kubectl name space
     export VAULT_K8S_NAMESPACE="vault-dev"
     kubectl create namespace $VAULT_K8S_NAMESPACE

     export VAULT_HELM_RELEASE_NAME="vault"
     export VAULT_SERVICE_NAME="vault-internal"
     export K8S_CLUSTER_NAME="cluster.local"
     export K8S_VAULT_CERT_SECRET_NAME="vault-ha-tls"
     export VAULT_NUM_REPLICAS=2
     ```
   2. ./prepare_tls.sh
   4. ./deploy_vault.sh
4. Initializing Vault 0:
   ```
   // Initialize vault.
   kubectl -n $VAULT_K8S_NAMESPACE exec $VAULT_HELM_RELEASE_NAME-0 -- vault operator init -key-shares=5 -key-threshold=3 -format=json > vault-cluster-keys.json
   ```
5. Unseal pods and join vault 0th node via raft to form cluster:
   ```
   ./useal_vault_pods.sh $VAULT_HELM_RELEASE_NAME-0

   // Make vault-1 and vault-2 join raft with vault-0.
   kubectl -n $VAULT_K8S_NAMESPACE exec -ti $VAULT_HELM_RELEASE_NAME-1 -- /bin/sh
   $> vault operator raft join -address=https://vault-1.vault-internal:8200 -leader-ca-cert="$(cat /vault/config/vault-ha-tls/vault.ca)" -leader-client-cert="$(cat /vault/config/vault-ha-tls/vault.crt)" -leader-client-key="$(cat /vault/config/vault-ha-tls/vault.key)" https://vault-0.vault-internal:8200

   kubectl -n $VAULT_K8S_NAMESPACE exec -ti $VAULT_HELM_RELEASE_NAME-2 -- /bin/sh
   $> vault operator raft join -address=https://vault-2.vault-internal:8200 -leader-ca-cert="$(cat /vault/config/vault-ha-tls/vault.ca)" -leader-client-cert="$(cat /vault/config/vault-ha-tls/vault.crt)" -leader-client-key="$(cat /vault/config/vault-ha-tls/vault.key)" https://vault-0.vault-internal:8200

   ./useal_vault_pods.sh $VAULT_HELM_RELEASE_NAME-1 3
   ./useal_vault_pods.sh $VAULT_HELM_RELEASE_NAME-2 3
   ```
6. Enable vault kv secrets engine, AppRole auth & kubernetes auth :s
   1. Setting required param:
      ```
      // Contact-Point for API server from vault pov:
      export KUBERNETES_SERVICE_HOST="kubernetes.default"
      export KUBERNETES_SERVICE_PORT=443

      // Secrets path for kv-2 engine for service account storing secrets.
      export SERVICE_ACCOUNT_SECRETS_PATH=service-accounts-secrets
      ```
   2. ./vault_service_enable_and_k8s_configurations.sh
7. Port forward vault service (in different terminal): `kubectl -n vault-dev port-forward service/vault 16189:8200`
   ```
   export VAULT_ADDR=https://127.0.0.1:16189
   export VAULT_TOKEN=$(cat vault-cluster-keys.json | jq -r ".root_token")
   export VAULT_SERVICE_METADATA_JSON=vault-secrets-service-metadata.json
   ```
8. ./create_service_account_secrets.sh
9. ./create_app_roles_for_service_account.sh