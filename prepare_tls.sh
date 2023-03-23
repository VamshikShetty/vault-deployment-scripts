
##
# Ref : https://developer.hashicorp.com/vault/tutorials/kubernetes/kubernetes-minikube-tls
##

# Create tmp dir to produce certificate.
mkdir -p ./tmp/vault

export WORKDIR=./tmp/vault

if [[ -z "${VAULT_K8S_NAMESPACE}" ]]; then
   echo "vault K8s namespace is not set."
   exit 1
fi

if [[ -z "${VAULT_HELM_RELEASE_NAME}" ]]; then
   echo "vault helm release name is not set."
   exit 1
fi

if [[ -z "${VAULT_SERVICE_NAME}" ]]; then
   echo "vault service name is not set."
   exit 1
fi

if [[ -z "${K8S_CLUSTER_NAME}" ]]; then
   echo "K8s cluster name is not set."
   exit 1
fi

if [[ -z "${K8S_VAULT_CERT_SECRET_NAME}" ]]; then
   echo "K8s vault cert secret name is not set."
   exit 1
fi

## Generate RSA private key.
openssl genrsa -out $WORKDIR/vault.key 2048

## Generate certificate signing request (CSR)
envsubst < templates/vault-csr.conf.template > $WORKDIR/vault-csr.conf

openssl req -new -key $WORKDIR/vault.key -config ${WORKDIR}/vault-csr.conf -out $WORKDIR/vault.csr

## Issue the certificate in K8s
export CSR_NAME=csr_vault
export CSR_SPEC_REQUEST=$(cat $WORKDIR/vault.csr|base64|tr -d '\n')
envsubst < templates/k8s-vault-csr.yaml.template > $WORKDIR/csr.yaml

kubectl delete csr $CSR_NAME
kubectl create -f $WORKDIR/csr.yaml
kubectl certificate approve $CSR_NAME

## Store certificates and key in K8s secret.

# Retrieve the certificate
kubectl get csr $CSR_NAME -o jsonpath='{.status.certificate}' | openssl base64 -d -A -out $WORKDIR/vault.crt

# Retrieve k8s CA certificate
kubectl config view \
   --raw \
   --minify \
   --flatten \
   -o jsonpath='{.clusters[].cluster.certificate-authority-data}' \
   | base64 -d > $WORKDIR/vault.ca

# Create the TLS K8s secret
kubectl -n $VAULT_K8S_NAMESPACE delete secret $K8S_VAULT_CERT_SECRET_NAME
kubectl create secret generic $K8S_VAULT_CERT_SECRET_NAME \
   -n $VAULT_K8S_NAMESPACE \
   --from-file=vault.key=$WORKDIR/vault.key \
   --from-file=vault.crt=$WORKDIR/vault.crt \
   --from-file=vault.ca=$WORKDIR/vault.ca

# Create Helm override values file.
envsubst < templates/helm-vault-raft-values.yaml.template > helm-vault-raft-values.yml