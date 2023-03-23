
if [[ -z "${KUBE_ADDR}" ]]; then
   echo "Kube address is not set."
   exit 1
fi

if [[ -z "${VAULT_K8S_NAMESPACE}" ]]; then
   echo "Vault K8s namespace is not set."
   exit 1
fi

if [[ -z "${VAULT_HELM_RELEASE_NAME}" ]]; then
   echo "Vault helm release name is not set."
   exit 1
fi


if [[ -z "${VAULT_NUM_REPLICAS}" ]]; then
   echo "Vault number of pods is not set."
   VAULT_NUM_REPLICAS=2
fi

# Add hashicorp helm repo.
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

# Deploy vault into k8s env.
helm install -n $VAULT_K8S_NAMESPACE $VAULT_HELM_RELEASE_NAME hashicorp/vault --values helm-vault-raft-values.yml

# Wait until pods are up and running.
vaultPodIsReady() {

   VAULT_POD_NAME=$1

   POD_STATUS_PHASE=$(curl http://$KUBE_ADDR/api/v1/namespaces/$VAULT_K8S_NAMESPACE/pods/$VAULT_POD_NAME | jq .status.phase | tr -d '"')
   if [[ $POD_STATUS_PHASE = "Running" ]]
   then
      POD_RETURN_VALUE=0
   else
      POD_RETURN_VALUE=1 # POD is not ready.
   fi
   echo "$POD_RETURN_VALUE"
}

vaultPodsAreReady() {
   ret=0
   for (( i=0; i < $VAULT_NUM_REPLICAS; i++ ))
   do 
      echo "checking status of $VAULT_NUM_REPLICAS-$i"
      val=$(vaultPodIsReady $VAULT_HELM_RELEASE_NAME-$i)
      ((ret = ret + $val))
   done
   echo "Number of pods yet to achieve running state : $ret"
   return $ret
}

i=0
until vaultPodsAreReady 
do
   echo "Waiting for Vault pods to be ready."
   sleep 20
   i=$((i+1))
   if [ $i == 40 ]
   then
      exit 1
   fi
done
