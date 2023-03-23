# Set params with default values if not set.
if [[ -z "${SERVICE_ACCOUNT_SECRETS_PATH}" ]]; then
    echo "secret's path for kv engine is not provided."
    exit 1
fi

if [[ -z "${VAULT_ADDR}" ]]; then
   echo "Kube vault port is not set."
   exit 1
fi
echo "Vault address : $VAULT_ADDR"

if [[ -z "${VAULT_TOKEN}" ]]; then
   echo "Vault token is not set."
   exit 1
fi

if [[ -z "${VAULT_SERVICE_METADATA_JSON}" ]]; then
   echo "Service metadata json is not provided."
   exit 1
fi

createServiceAppPolicyAndRole() {
   LOCAL_SECRETS_PATH=$1
   LOCAL_POLICY_VALID_OVER_ROLE=$2
   LOCAL_SERVICE_NAME=$3
   LOCAL_SERVICE_K8S_NAMESPACE=$4

   # Create service name if it doesn't exists.
   kubectl create namespace $LOCAL_SERVICE_K8S_NAMESPACE

   # Create a policy to read secrets path of give service app.
   echo "Creating role ID and service account for $LOCAL_SERVICE_NAME app, with policy over path : $LOCAL_SECRETS_PATH"
   POLICY_PAYLOAD=$(sed "s/{service-account-secrets-path}/$LOCAL_SECRETS_PATH\/data\/apps\/$LOCAL_POLICY_VALID_OVER_ROLE/" templates/secrets-path-read-policy-payload.template)

   APP_ROLE_POLICY=$LOCAL_SERVICE_NAME-secrets-read-policy

   echo "Creating Policy called $APP_ROLE_POLICY with payload : $POLICY_PAYLOAD"

   curl --insecure \
      --header "X-Vault-Token: $VAULT_TOKEN" \
      --request POST \
      --data "$POLICY_PAYLOAD" \
      $VAULT_ADDR/v1/sys/policy/$APP_ROLE_POLICY

   # Create app role
   ROLE_CREATE_PAYLOAD=$(sed "s/{service-name-role-read-policy}/$APP_ROLE_POLICY/" templates/create-approle-payload.template)

   echo "Creating app role [auth/approle/role/$LOCAL_SERVICE_NAME-role-id] with payload : $ROLE_CREATE_PAYLOAD"
   curl --insecure \
      --header "X-Vault-Token: $VAULT_TOKEN" \
      --request POST \
      --data "$ROLE_CREATE_PAYLOAD" \
      $VAULT_ADDR/v1/auth/approle/role/$LOCAL_SERVICE_NAME-role-id

   # Now create a policy which has read privilege over : auth/approle/role/$LOCAL_SERVICE_NAME-role-id
   POLICY_PAYLOAD=$(sed -e "s/{approle-path}/auth\/approle\/role\/$LOCAL_SERVICE_NAME-role-id/" templates/k8s-read-approle-path-policy-payload.template)
   K8S_SVC_ACCOUNT_ROLE_POLICY=$LOCAL_SERVICE_NAME-svc-acccount-read-auth-approle-policy

   echo "Creating k8s policy [$K8S_SVC_ACCOUNT_ROLE_POLICY] with payload : $POLICY_PAYLOAD"

   curl --insecure \
      --header "X-Vault-Token: $VAULT_TOKEN" \
      --request POST \
      --data "$POLICY_PAYLOAD" \
      $VAULT_ADDR/v1/sys/policy/$K8S_SVC_ACCOUNT_ROLE_POLICY

   # Create a role which authorizes the `$LOCAL_SERVICE_NAME-svcacc` service account in the default namespace and it gives it the default policy.
   K8S_SERVICE_ACCOUNT=$LOCAL_SERVICE_NAME-k8s-svcacc
   K8S_ROLE_CREATE_PAYLOAD=$(sed -e "s/{service-name-k8s-auth-role-policy}/$K8S_SVC_ACCOUNT_ROLE_POLICY/" -e "s/{k8s-service-account-name}/$K8S_SERVICE_ACCOUNT/" -e "s/{k8s-namespace}/$LOCAL_SERVICE_K8S_NAMESPACE/" templates/create-auth-k8s-payload.template)

   echo "Creating k8s role [auth/kubernetes/role/$LOCAL_SERVICE_NAME-svcacc-role] with payload : $K8S_ROLE_CREATE_PAYLOAD"
   curl --insecure \
      --header "X-Vault-Token: $VAULT_TOKEN" \
      --request POST \
      --data "$K8S_ROLE_CREATE_PAYLOAD" \
      $VAULT_ADDR/v1/auth/kubernetes/role/$LOCAL_SERVICE_NAME-svcacc-role

   # Lets create a Kubernetes service account named `$LOCAL_SERVICE_NAME-svcacc` in the default namespace as stated in the vault policy
   kubectl -n $LOCAL_SERVICE_K8S_NAMESPACE delete serviceaccount $K8S_SERVICE_ACCOUNT
   kubectl -n $LOCAL_SERVICE_K8S_NAMESPACE create serviceaccount $K8S_SERVICE_ACCOUNT

   # Get service account token from kubernetes.
   JWT_TOKEN=$(kubectl -n $LOCAL_SERVICE_K8S_NAMESPACE create token $K8S_SERVICE_ACCOUNT)

   # Get k8s auth login token from vault.
   K8S_AUTH_LOGIN_PAYLOAD=$(sed -e "s/{role}/$LOCAL_SERVICE_NAME-svcacc-role/" -e "s/{jwt}/$JWT_TOKEN/" templates/k8s-auth-role-jwt-login.template)

   echo "Using service account JWT token perform kubernetes auth login for role : $LOCAL_SERVICE_NAME-svcacc-role :"
   CLIENT_TOKEN=$(curl --insecure --request POST --data "$K8S_AUTH_LOGIN_PAYLOAD" $VAULT_ADDR/v1/auth/kubernetes/login | jq .auth.client_token | tr -d '"')

   # Read App role ID
   ROLE_ID=$(curl --insecure --header "X-Vault-Token: $CLIENT_TOKEN" $VAULT_ADDR/v1/auth/approle/role/$LOCAL_SERVICE_NAME-role-id/role-id | jq -r .data.role_id)
   echo "Create role [$ROLE_ID] for service : $LOCAL_SERVICE_NAME"

   # Create specific K8s secrets containing role id for individual service accounts.
   kubectl -n $LOCAL_SERVICE_K8S_NAMESPACE delete secret $LOCAL_SERVICE_NAME-role
   kubectl -n $LOCAL_SERVICE_K8S_NAMESPACE create secret generic $LOCAL_SERVICE_NAME-role --from-literal=role_id=$ROLE_ID

   # # TODO : REMOVE THIS ! (only needed for testing)
   # SECRET_ID=$(curl --insecure  --request POST --header "X-Vault-Token: $CLIENT_TOKEN" $VAULT_ADDR/v1/auth/approle/role/$LOCAL_SERVICE_NAME-role-id/secret-id | jq -r .data.secret_id)

   # KV_ACCESS_TOKEN=$(curl --insecure --request POST --data "{ \"role_id\" : \"$ROLE_ID\", \"secret_id\" : \"$SECRET_ID\" }" $VAULT_ADDR/v1/auth/approle/login | jq -r .auth.client_token)
   # echo "KV Access token : $KV_ACCESS_TOKEN"

   # PASSWORD=$(curl --insecure --header "X-Vault-Token: $KV_ACCESS_TOKEN" $VAULT_ADDR/v1/$LOCAL_SECRETS_PATH/data/apps/$LOCAL_SERVICE_NAME?version=0 | jq -r .data.data.password)

   # echo "Service app [LOCAL_SERVICE_NAME] : $PASSWORD"
}

# Create policy to access paths for each role : https://developer.hashicorp.com/vault/docs/concepts/policies
jq -c '.service_apps[]' $VAULT_SERVICE_METADATA_JSON | while read service_metadata; do
   SERVICE_NAME=$( echo "$service_metadata" | jq -r ".name")
   POLICY_VALID_OVER=$( echo "$service_metadata" | jq -r ".policy_valid_over")
   SERVICE_K8S_NAMESPACE=$( echo "$service_metadata" | jq -r ".namespace")

   echo "Creating roles, service acccount and K8s secrets for : $SERVICE_NAME over policy area [/$POLICY_VALID_OVER]"
   createServiceAppPolicyAndRole "$SERVICE_ACCOUNT_SECRETS_PATH" "$POLICY_VALID_OVER" "$SERVICE_NAME" "$SERVICE_K8S_NAMESPACE"
done