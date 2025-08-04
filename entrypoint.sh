#!/bin/bash

set -e

if [ ! -z ${PATH_OVERRIDE+x} ]; then
	export PATH=${PATH_OVERRIDE}:${PATH}
fi;

## Install required versions
apt-get update && apt-get install -y \
	kubectl=${KUBECTL_VERSION}-1 \
	chamber=${CHAMBER_VERSION}-1 \
	helm=${HELM_VERSION}-1

helm plugin install https://github.com/databus23/helm-diff --version v${HELM_DIFF_VERSION} \
	&& helm plugin install https://github.com/aslafy-z/helm-git --version ${HELM_GIT_VERSION} \
	&& helm plugin install https://github.com/jkroepke/helm-secrets --version v${HELM_SECRETS_VERSION} \
	&& helm plugin install https://github.com/hypnoglow/helm-s3 --version v${HELM_S3_VERSION} \
	&& rm -rf $XDG_CACHE_HOME/helm

# Install Helmfile based on architecture and OS
if [[ -z "$HELMFILE_VERSION" ]]; then
  echo "HELMFILE_VERSION is not set. Exiting."
  exit 1
fi

# Determine target OS and architecture, fallback if not set
OS="${TARGETOS:-linux}"
ARCH="${TARGETARCH:-amd64}"

# Map Docker arch to Helmfile naming
if [[ "$ARCH" == "amd64" ]]; then
  ARCH_NAME="amd64"
elif [[ "$ARCH" == "arm64" ]]; then
  ARCH_NAME="arm64"
else
  echo "Unsupported architecture: $ARCH"
  exit 1
fi

HELMFILE_URL="https://github.com/helmfile/helmfile/releases/download/v${HELMFILE_VERSION}/helmfile_${HELMFILE_VERSION}_${OS}_${ARCH_NAME}.tar.gz"

echo "Downloading Helmfile from: $HELMFILE_URL"
curl -L "$HELMFILE_URL" -o helmfile.tar.gz
tar -xzf helmfile.tar.gz
chmod +x helmfile
mv helmfile /usr/local/bin/helmfile
rm helmfile.tar.gz

echo "Helmfile installed at: /usr/local/bin/helmfile"

# Used for debugging
aws ${AWS_ENDPOINT_OVERRIDE:+--endpoint-url $AWS_ENDPOINT_OVERRIDE} sts --region ${AWS_REGION} get-caller-identity

# Login to Kubernetes Cluster.
aws ${AWS_ENDPOINT_OVERRIDE:+--endpoint-url $AWS_ENDPOINT_OVERRIDE} eks --region ${AWS_REGION} update-kubeconfig --name ${CLUSTER_NAME}

# Read platform specific configs/info
chamber export platform/${CLUSTER_NAME}/${ENVIRONMENT} --format yaml | yq --exit-status --no-colors  eval '{"platform": .}' - > /tmp/platform.yaml

APPLICATION_HELMFILE=$(pwd)/${HELMFILE_PATH}/${HELMFILE}

BASIC_ARGS="--environment ${ENVIRONMENT} --file ${APPLICATION_HELMFILE} --state-values-file /tmp/platform.yaml"
EXTRA_VALUES_ARGS=""
DEBUG_ARGS=""

echo "Kubeconfig:"
cat ~/.kube/config

echo "AWS identity:"
aws sts get-caller-identity

echo "Current context:"
kubectl config current-context

echo "Can we talk to the cluster?"
kubectl get ns || echo "kubectl failed"

kubectl get nodes -v=10

echo "Check env for helm:"
env | grep AWS_

if [[ "${HELM_DEBUG}" == "true" ]]; then
	DEBUG_ARGS=" --debug"
fi

if [[ -n "$HELM_VALUES_YAML" ]]; then
  echo -e "Using extra values:\n${HELM_VALUES_YAML}"
  HELM_VALUES_FILE="/tmp/extra_helm_values.yml"
  echo "$HELM_VALUES_YAML" > "$HELM_VALUES_FILE"
  EXTRA_VALUES_ARGS="--state-values-file /tmp/extra_helm_values.yml"
fi

if [[ "${OPERATION}" == "deploy" ]]; then
	OPERATION_COMMAND="helmfile ${BASIC_ARGS} ${EXTRA_VALUES_ARGS} ${DEBUG_ARGS} apply"
	echo "Executing: ${OPERATION_COMMAND}"
	${OPERATION_COMMAND}

	RELEASES=$(helmfile ${BASIC_ARGS} ${EXTRA_VALUES_ARGS} ${DEBUG_ARGS} list --output json | jq .[].name -r)
  for RELEASE in ${RELEASES}
  do
    echo "Processing release: ${RELEASE}"
    echo "Executing kubectl command: kubectl --namespace ${NAMESPACE} get -l ${RELEASE_LABEL_NAME}=${RELEASE} ${URL_RESOURCE_TYPE} -o json"
    ENTRYPOINT=$(kubectl --namespace ${NAMESPACE} get -l ${RELEASE_LABEL_NAME}=${RELEASE} ${URL_RESOURCE_TYPE} -o json | jq --raw-output '[.items[].metadata.annotations["outputs.webapp-url"]] | first')
    if [[ "${ENTRYPOINT}" != "" ]]; then
      echo "Found webapp-url for release ${RELEASE}: ${ENTRYPOINT}"
      echo "webapp-url=${ENTRYPOINT}" >> $GITHUB_OUTPUT
    else
      echo "No webapp-url found for release ${RELEASE}"
    fi
  done


elif [[ "${OPERATION}" == "destroy" ]]; then

	set +e
	kubectl get ns ${NAMESPACE}
	NAMESPACE_EXISTS=$?
	set -e

	if [[ ${NAMESPACE_EXISTS} -eq 0  ]]; then
		OPERATION_COMMAND="helmfile ${BASIC_ARGS} ${EXTRA_VALUES_ARGS} ${DEBUG_ARGS} destroy"
		echo "Executing: ${OPERATION_COMMAND}"
		${OPERATION_COMMAND}

		RELEASES_COUNTS=$(helm --namespace ${NAMESPACE} list --output json | jq 'length')

    if [[ "${RELEASES_COUNTS}" == "0" ]]; then
    	kubectl delete ns ${NAMESPACE}
    fi
  fi
fi
