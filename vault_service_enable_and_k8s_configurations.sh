# Set params with default values if not set.
if [[ -z "${SERVICE_ACCOUNT_SECRETS_PATH}" ]]; then
    echo "secret's path for kv engine is not provided."
    exit 1
fi

if [[ -z "${KUBERNETES_SERVICE_HOST}" ]]; then
   echo "Kube service host is not set."
   exit 1
fi

if [[ -z "${KUBERNETES_SERVICE_PORT}" ]]; then
   echo "Kube service port is not set."
   exit 1
fi

if [[ -z "${VAULT_K8S_NAMESPACE}" ]]; then
   echo "Vault K8s namespace is not set."
   exit 1
fi

# Read vault tokens.
VAULT_ROOT_TOKEN=$(cat vault-cluster-keys.json | jq -r ".root_token")

# Login into vault.
kubectl -n $VAULT_K8S_NAMESPACE exec vault-0 -- vault login -no-print $VAULT_ROOT_TOKEN

# Enable key-value secrets engine.
kubectl -n $VAULT_K8S_NAMESPACE exec vault-0 -- vault secrets enable -path=$SERVICE_ACCOUNT_SECRETS_PATH kv-v2

# Enable AppRole OIDC for each service account : https://developer.hashicorp.com/vault/docs/auth/approle
kubectl -n $VAULT_K8S_NAMESPACE exec vault-0 -- vault auth enable approle

# Enable kubernetes auth to fetch secret ID during application startup : https://developer.hashicorp.com/vault/docs/auth/kubernetes
kubectl -n $VAULT_K8S_NAMESPACE exec vault-0 -- vault auth enable kubernetes

# Use the /config endpoint to configure Vault to talk to Kubernetes.
# Use local service account token as the reviewer JWT, by omitting
# token_reviewer_jwt and kubernetes_ca_cert when configuring the auth method.
kubectl -n $VAULT_K8S_NAMESPACE exec vault-0 -- vault write auth/kubernetes/config \
    kubernetes_host=https://$KUBERNETES_SERVICE_HOST:$KUBERNETES_SERVICE_PORT
