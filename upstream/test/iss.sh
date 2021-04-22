#!/bin/bash
set +o pipefail

# iss.sh  (Index Sync Sha)

OP_TEST_INDEX_IMAGE_TAG=${2-"latest"}

OP_TEST_BASE_DEP="ansible curl openssl git"

OP_TEST_IMAGE=${OP_TEST_IMAGE-"quay.io/operator_testing/operator-test-playbooks:latest"}
OP_TEST_CONTAINER_TOOL=${OP_TEST_CONTAINER_TOOL-"docker"}
OP_TEST_CONTAINER_OPT=${OP_TEST_CONTAINER_OPT-"-it"}
OP_TEST_NAME=${OPT_TEST_NAME-"op-sync-sha"}
OP_TEST_ANSIBLE_PULL_REPO=${OP_TEST_ANSIBLE_PULL_REPO-"https://github.com/operator-framework/operator-test-playbooks"}
OP_TEST_ANSIBLE_PULL_BRANCH=${OP_TEST_ANSIBLE_PULL_BRANCH-"master"}
OP_TEST_ANSIBLE_DEFAULT_ARGS=${OP_TEST_ANSIBLE_DEFAULT_ARGS-"-i localhost, -e ansible_connection=local -e run_upstream=true -e run_remove_catalog_repo=false upstream/local.yml"}
OP_TEST_ANSIBLE_EXTRA_ARGS=${OP_TEST_ANSIBLE_EXTRA_ARGS-"--tags sync_index_sha"}
OP_TEST_CONAINER_RUN_DEFAULT_ARGS=${OP_TEST_CONAINER_RUN_DEFAULT_ARGS-"--net host --cap-add SYS_ADMIN --cap-add SYS_RESOURCE --security-opt seccomp=unconfined --security-opt label=disable -e STORAGE_DRIVER=vfs -e BUILDAH_FORMAT=docker -e GODEBUG-x509ignoreCN=0"}
OP_TEST_CONTAINER_RUN_EXTRA_ARGS=${OP_TEST_CONTAINER_RUN_EXTRA_ARGS-""}
OP_TEST_EXEC_USER=${OP_TEST_EXEC_USER-""}
OP_TEST_EXEC_USER_SECRETS=${OP_TEST_EXEC_USER_SECRETS-""}
OP_TEST_EXEC_BASE=${OP_TEST_EXEC_BASE-"ansible-playbook -i localhost, -e ansible_connection=local upstream/local.yml -e run_upstream=true -e image_protocol='docker://'"}
OP_TEST_EXEC_EXTRA=${OP_TEST_EXEC_EXTRA-"-e container_tool=podman"}
OP_TEST_INDEX_POSTFIX=${OP_TEST_INDEX_POSTFIX-"s"}

#$OP_TEST_CONTAINER_TOOL rm -f $OP_TEST_NAME > /dev/null 2>&1

if [ "$1" == "kubernetes" ];then
  OP_TEST_EXEC_USER="-e sis_index_image_input=quay.io/operatorhubio/catalog:$OP_TEST_INDEX_IMAGE_TAG -e sis_index_image_output=quay.io/operatorhubio/catalog:${OP_TEST_INDEX_IMAGE_TAG}${OP_TEST_INDEX_POSTFIX} -e op_base_name=upstream-community-operators"
  OP_TEST_EXEC_USER_SECRETS="-e quay_api_token=$QUAY_API_TOKEN_OPERATORHUBIO"
elif [ "$1" == "openshift" ];then
  OP_TEST_EXEC_USER="-e sis_index_image_input=quay.io/openshift-community-operators/catalog:$OP_TEST_INDEX_IMAGE_TAG -e sis_index_image_output=quay.io/openshift-community-operators/catalog:${OP_TEST_INDEX_IMAGE_TAG}${OP_TEST_INDEX_POSTFIX} -e op_base_name=community-operators"
  OP_TEST_EXEC_USER_SECRETS="-e quay_api_token=$QUAY_API_TOKEN_OPENSHIFT_COMMUNITY_OP"
else
  echo "Only supported input is 'kubernetes' or 'openshift'"
  exit 1
fi

$OP_TEST_CONTAINER_TOOL run -d --rm $OP_TEST_CONTAINER_OPT --name $OP_TEST_NAME $OP_TEST_CONAINER_RUN_DEFAULT_ARGS $OP_TEST_CONTAINER_RUN_EXTRA_ARGS $OP_TEST_IMAGE
$OP_TEST_CONTAINER_TOOL exec $OP_TEST_CONTAINER_OPT $OP_TEST_NAME /bin/bash -c "$OP_TEST_EXEC_BASE $OP_TEST_EXEC_EXTRA $OP_TEST_EXEC_USER $OP_TEST_EXEC_USER_SECRETS"
