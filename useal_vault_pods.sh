
VAULT_POD=$1
VAULT_KEY_THRESHOLD=$2

if [[ -z "$VAULT_POD" ]]; then
   echo "Setting Vault POD to unseal not set."
   exit 1
fi

if [[ -z "${VAULT_KEY_THRESHOLD}" ]]; then
   echo "Setting Vault unseal key threshold"
   VAULT_KEY_THRESHOLD=3
fi

if [[ -z "${VAULT_K8S_NAMESPACE}" ]]; then
   echo "Vault K8s namespace is not set."
   exit 1
fi

# perform unseal of vault using threshold number of keys. 
echo "Unsealing vaults."

unseal() {
   VAULT_POD=$1
   LOCAL_VAULT_KEY_THRESHOLD=$2

   declare -A unseal_keys
   for ((i = 0; i < $LOCAL_VAULT_KEY_THRESHOLD; i++ ));
   do
      unseal_keys[$i]=$(jq -r ".unseal_keys_b64[$i]" vault-cluster-keys.json)
      kubectl -n $VAULT_K8S_NAMESPACE exec $VAULT_POD -- vault operator unseal ${unseal_keys[$i]}
   done
}

unseal $VAULT_POD $VAULT_KEY_THRESHOLD