# Set params with default values if not set.
if [[ -z "${SERVICE_ACCOUNT_SECRETS_PATH}" ]]; then
    echo "secret's path for kv engine is not provided."
    exit 1
fi

if [[ -z "${VAULT_ADDR}" ]]; then
   echo "Kube vault address is not set."
   exit 1
fi

if [[ -z "${VAULT_SERVICE_METADATA_JSON}" ]]; then
   echo "Service metadata json is not provided."
   exit 1
fi

# Read vault tokens.
VAULT_ROOT_TOKEN=$(cat vault-cluster-keys.json | jq -r ".root_token")

# Store password corresponding each service app.
jq -c '.service_apps[]' $VAULT_SERVICE_METADATA_JSON | while read service_metadata; do
    SERVICE_NAME=$( echo "$service_metadata" | jq -r ".name")
    SERVICE_PASSWORD=$( openssl rand -hex 30 )

    curl --insecure --header "X-Vault-Token: $VAULT_ROOT_TOKEN" --request POST --data "{ \"data\": { \"password\" : \"$SERVICE_PASSWORD\"}}" $VAULT_ADDR/v1/$SERVICE_ACCOUNT_SECRETS_PATH/data/apps/$SERVICE_NAME
done
