#!/bin/bash
set +o pipefail

ACTION=${1-""}
TESTS=$1

[[ $TESTS == all* ]] && TESTS="kiwi,lemon,orange"
TESTS=${TESTS//,/ }
OP_SCRIPT_URL=${OP_SCRIPT_URL-"https://cutt.ly/WhkV76k"}

OP_TEST_BASE_DEP="ansible curl openssl git"

OP_TEST_IMAGE=${OP_TEST_IMAGE-"quay.io/operator_testing/operator-test-playbooks:latest"}
OP_TEST_CERT_DIR=${OP_TEST_CERT_DIR-"/tmp/certs"}
OP_TEST_CONTAINER_TOOL=${OP_TEST_CONTAINER_TOOL-"docker"}
OP_TEST_CONTAINER_OPT=${OP_TEST_CONTAINER_OPT-"-it"}
OP_TEST_NAME=${OPT_TEST_NAME-"op-test"}
# OP_TEST_ANSIBLE_PULL_REPO=${OP_TEST_ANSIBLE_PULL_REPO-"https://github.com/redhat-operator-ecosystem/operator-test-playbooks"}
# OP_TEST_ANSIBLE_PULL_BRANCH=${OP_TEST_ANSIBLE_PULL_BRANCH-"upstream-community"}
OP_TEST_ANSIBLE_PULL_REPO=${OP_TEST_ANSIBLE_PULL_REPO-"https://github.com/operator-framework/operator-test-playbooks"}
OP_TEST_ANSIBLE_PULL_BRANCH=${OP_TEST_ANSIBLE_PULL_BRANCH-"master"}
OP_TEST_ANSIBLE_DEFAULT_ARGS=${OP_TEST_ANSIBLE_DEFAULT_ARGS-"-i localhost, -e ansible_connection=local -e run_upstream=true -e run_remove_catalog_repo=false upstream/local.yml"}
OP_TEST_ANSIBLE_EXTRA_ARGS=${OP_TEST_ANSIBLE_EXTRA_ARGS-"--tags kubectl,install_kind"}
OP_TEST_CONAINER_RUN_DEFAULT_ARGS=${OP_TEST_CONAINER_RUN_DEFAULT_ARGS-"--net host --cap-add SYS_ADMIN --cap-add SYS_RESOURCE --security-opt seccomp=unconfined --security-opt label=disable -v $OP_TEST_CERT_DIR/domain.crt:/usr/share/pki/ca-trust-source/anchors/ca.crt -e STORAGE_DRIVER=vfs -e BUILDAH_FORMAT=docker"}
OP_TEST_CONTAINER_RUN_EXTRA_ARGS=${OP_TEST_CONTAINER_RUN_EXTRA_ARGS-""}
OP_TEST_CONTAINER_EXEC_DEFAULT_ARGS=${OP_TEST_CONTAINER_EXEC_DEFAULT_ARGS-""}
OP_TEST_CONTAINER_EXEC_EXTRA_ARGS=${OP_TEST_CONTAINER_EXEC_EXTRA_ARGS-""}
OP_TEST_EXEC_BASE=${OP_TEST_EXEC_BASE-"ansible-playbook -i localhost, -e ansible_connection=local upstream/local.yml -e run_upstream=true -e image_protocol='docker://'"}
OP_TEST_EXEC_EXTRA=${OP_TEST_EXEC_EXTRA-"-e container_tool=podman"}
# OP_TEST_EXEC_EXTRA=${OP_TEST_EXEC_EXTRA-""}
OP_TEST_RUN_MODE=${OP_TEST_RUN_MODE-"privileged"}
OP_TEST_LABELS=${OP_TEST_LABELS-""}
OP_TEST_PROD=${OP_TEST_PROD-0}
OP_TEST_DEBUG=${OP_TEST_DEBUG-0}
OP_TEST_DRY_RUN=${OP_TEST_DRY_RUN-0}
OP_TEST_FORCE_INSTALL=${OP_TEST_FORCE_INSTALL-0}
OP_TEST_RESET=${OP_TEST_RESET-1}
OP_TEST_LOG_DIR=${OP_TEST_LOG_DIR-"/tmp/op-test"}
OP_TEST_NOCOLOR=${OP_TEST_NOCOLOR-0}

OP_TEST_VER_OVERWRITE=${OP_TEST_VER_OVERWRITE-0}
OP_TEST_RECREATE=${OP_TEST_RECREATE-0}
OP_TEST_FORCE_DEPLOY_ON_K8S=${OP_TEST_FORCE_DEPLOY_ON_K8S-0}
OP_TEST_UNCOMPLETE="/tmp/operators_uncomplete-localhost.yaml"


[[ $OP_TEST_NOCOLOR -eq 1 ]] && ANSIBLE_NOCOLOR=1

function help() {
    echo ""
    echo "op-test <test1,test2,...,testN> [<rebo>] [<branch>]"
    echo ""
    echo "Note: 'op-test' can be substituted by 'bash <(curl -sL $OP_SCRIPT_URL)'"
    echo ""
    echo -e "Examples:\n"
    echo -e "\top-test all upstream-community-operators/aqua/1.0.2\n"
    echo -e "\top-test all upstream-community-operators/aqua/1.0.2 https://github.com/operator-framework/community-operators master\n"
    echo -e "\top-test kiwi upstream-community-operators/aqua/1.0.2 https://github.com/operator-framework/community-operators master\n"
    echo -e "\top-test lemon,orange upstream-community-operators/aqua/1.0.2 https://github.com/operator-framework/community-operators master\n"
    exit 1
}

function checkExecutable() {
    local pm=""
    for p in $*;do
        ! command -v $p > /dev/null 2>&1 && pm="$p $pm"
    done
    if [[ "$pm" != "" ]]; then
        echo "Error: Folowing packages needs to be installed !!!"
        for p in $pm;do
            echo -e "\t$p\n"
        done
        echo ""
        exit 1
    fi
}

function clean() {
    echo "Removing testing container '$OP_TEST_NAME' ..."
    $OP_TEST_CONTAINER_TOOL rm -f $OP_TEST_NAME > /dev/null 2>&1
    echo "Removing kind registry 'kind-registry' ..."
    $OP_TEST_CONTAINER_TOOL rm -f kind-registry > /dev/null 2>&1
    command -v kind > /dev/null 2>&1 && kind delete cluster --name operator-test
    echo "Removing cert dir '$OP_TEST_CERT_DIR' ..."
    rm -rf $OP_TEST_CERT_DIR > /dev/null 2>&1
    echo "Done"
    exit 0
}

run() {
        if [[ $OP_TEST_DEBUG -ge 4 ]] ; then
                v=$(exec 2>&1 && set -x && set -- "$@")
                echo "#${v#*--}"
                set -o pipefail
                "$@" | tee -a $OP_TEST_LOG_DIR/log.out
                [[ $? -eq 0 ]] || { echo -e "\nFailed with rc=$? !!!\nLogs are in '$OP_TEST_LOG_DIR/log.out'."; exit $?; }
                set +o pipefail
        elif [[ $OP_TEST_DEBUG -ge 1 ]] ; then
                set -o pipefail
                "$@" | tee -a $OP_TEST_LOG_DIR/log.out
                [[ $? -eq 0 ]] || { echo -e "\nFailed with rc=$? !!!\nLogs are in '$OP_TEST_LOG_DIR/log.out'."; exit $?; }
                set +o pipefail
        else
                set -o pipefail
                "$@" | tee -a $OP_TEST_LOG_DIR/log.out >/dev/null 2>&1
                [[ $? -eq 0 ]] || { echo -e "\nFailed with rc=$? !!!\nLogs are in '$OP_TEST_LOG_DIR/log.out'."; exit $?; }
                set +o pipefail
        fi
}

[ "$OP_TEST_RUN_MODE" = "privileged" ] && OP_TEST_CONAINER_RUN_DEFAULT_ARGS="--privileged --net host -v $OP_TEST_CERT_DIR:/usr/share/pki/ca-trust-source/anchors -e STORAGE_DRIVER=vfs -e BUILDAH_FORMAT=docker"
[ "$OP_TEST_RUN_MODE" = "user" ] && OP_TEST_CONAINER_RUN_DEFAULT_ARGS="--net host -v $OP_TEST_CERT_DIR:/usr/share/pki/ca-trust-source/anchors -e STORAGE_DRIVER=vfs -e BUILDAH_FORMAT=docker"

# OP_TEST_EXEC_USER="-e operator_dir=/tmp/community-operators-for-catalog/upstream-community-operators/aqua -e operator_version=1.0.2 --tags pure_test"

checkExecutable $OP_TEST_BASE_DEP

if ! command -v ansible > /dev/null 2>&1; then
    echo "Error: Ansible is not installed. Please install it first !!!"
    echo "    e.g.  : pip install ansible jmespath"
    echo "    or    : apt install ansible"
    echo "    or    : yum install ansible"
    echo -e "\nRun 'ansible --version' to make sure it is installed\n"

    exit 1
fi

if [ "$OP_TEST_CONTAINER_TOOL" = "podman" ];then
    OP_TEST_ANSIBLE_EXTRA_ARGS="$OP_TEST_ANSIBLE_EXTRA_ARGS -e opm_container_tool=podman -e container_tool=podman -e opm_container_tool_index=none"
    # OP_TEST_EXEC_EXTRA="$OP_TEST_EXEC_EXTRA -e opm_container_tool=podman -e container_tool=podman -e opm_container_tool_index="
fi

[ -d $OP_TEST_LOG_DIR ] || mkdir -p $OP_TEST_LOG_DIR
[ -f $OP_TEST_LOG_DIR/log.out ] && rm -f $OP_TEST_LOG_DIR/log.out

# Handle labels
if [ -n "$OP_TEST_LABELS" ];then
    for l in $(echo $OP_TEST_LABELS);do
    echo "Handling label '$l' ..."
    [[ "$l" = "allow/operator-version-overwrite" ]] && export OP_TEST_VER_OVERWRITE=1
    [[ "$l" = "allow/operator-recreate" ]] && export OP_TEST_RECREATE=1
    [[ "$l" = "test/force-deploy-on-kubernetes" ]] && export OP_TEST_FORCE_DEPLOY_ON_K8S=1
    [[ "$l" = "verbosity/high" ]] && export OP_TEST_DEBUG=2
    [[ "$l" = "verbosity/debug" ]] && export OP_TEST_DEBUG=3
    done
else
    echo "Info: No labels defined"
fi
[[ $OP_TEST_DEBUG -eq 0 ]] && OP_TEST_EXEC_EXTRA="-vv $OP_TEST_EXEC_EXTRA"
# [[ $OP_TEST_DEBUG -eq 1 ]] && OP_TEST_EXEC_EXTRA="$OP_TEST_EXEC_EXTRA"
[[ $OP_TEST_DEBUG -eq 2 ]] && OP_TEST_EXEC_EXTRA="-v $OP_TEST_EXEC_EXTRA"
[[ $OP_TEST_DEBUG -eq 3 ]] && OP_TEST_EXEC_EXTRA="-vv $OP_TEST_EXEC_EXTRA"
[[ $OP_TEST_DRY_RUN -eq 1 ]] && DRY_RUN_CMD="echo"

echo "debug=$OP_TEST_DEBUG"

# Handle test types
[ -z $1 ] && help

[ "$ACTION" = "clean" ] && clean
if [ "$ACTION" = "docker" ];then
    echo "Installing docker ..."
    $DRY_RUN_CMD ansible-pull -U $OP_TEST_ANSIBLE_PULL_REPO -C $OP_TEST_ANSIBLE_PULL_BRANCH $OP_TEST_ANSIBLE_DEFAULT_ARGS -e run_prepare_catalog_repo_upstream=false --tags docker
    if [[ $? -eq 0 ]];then
        echo -e "\n=================================================================================="
        echo -e "Make sure that you logout and login after docker installation to apply changes !!!"
        echo -e "==================================================================================\n"
    else
        echo "Problem installing docker !!!"
        exit 1
    fi
    exit 0
fi
if ! command -v $OP_TEST_CONTAINER_TOOL > /dev/null 2>&1; then
    echo -e "\nError: '$OP_TEST_CONTAINER_TOOL' is missing !!! Install it via:"
    [ "$OP_TEST_CONTAINER_TOOL" = "docker" ] && echo -e "\n\tbash <(curl -sL $OP_SCRIPT_URL) $OP_TEST_CONTAINER_TOOL"
    [ "$OP_TEST_CONTAINER_TOOL" = "podman" ] && echo -e "\n\tContainer tool '$OP_TEST_CONTAINER_TOOL' is not supported yet"
    echo
    exit 1
fi


# Handle operator info
OP_TEST_BASE_DIR=${OP_TEST_BASE_DIR-"/tmp/community-operators-for-catalog"}
OP_TEST_STREAM=${OP_TEST_STREAM-"upstream-community-operators"}
OP_TEST_OPERATOR=${OP_TEST_OPERATOR-"aqua"}
OP_TEST_VERSION=${OP_TEST_VERSION-"1.0.2"}

if [ -n "$2" ];then
    if [ -n "$3" ];then
        p=$2
        OP_TEST_VERSION=$(echo $p | rev | cut -d'/' -f 1 | rev);p=$(dirname $p)
        OP_TEST_OPERATOR=$(echo $p | rev | cut -d'/' -f 1 | rev);p=$(dirname $p)
        OP_TEST_STREAM=$(echo $p | rev | cut -d'/' -f 1 | rev);p=$(dirname $p)
        OP_TEST_REPO="$3"
        OP_TEST_BRANCH="master"
        [ -n "$4" ] && OP_TEST_BRANCH=$4
    elif [ -d $2 ];then
        p=$(readlink -f $2)
        OP_TEST_VERSION=$(echo $p | rev | cut -d'/' -f 1 | rev);p=$(dirname $p)
        OP_TEST_OPERATOR=$(echo $p | rev | cut -d'/' -f 1 | rev);p=$(dirname $p)
        OP_TEST_STREAM=$(echo $p | rev | cut -d'/' -f 1 | rev);p=$(dirname $p)
        OP_TEST_CONTAINER_RUN_EXTRA_ARGS="$OP_TEST_CONTAINER_RUN_EXTRA_ARGS -v $p:/tmp/community-operators-for-catalog"
    else
        echo -e "\nError: Full path to operator/version '$PWD/$2' was not found !!!\n"
        exit 1
    fi

else
    p=${PWD}
    echo "Running locally from '$p' ..."
    OP_TEST_VERSION=$(echo $p | rev | cut -d'/' -f 1 | rev);p=$(dirname $p)
    OP_TEST_OPERATOR=$(echo $p | rev | cut -d'/' -f 1 | rev);p=$(dirname $p)
    OP_TEST_STREAM=$(echo $p | rev | cut -d'/' -f 1 | rev);p=$(dirname $p)
    OP_TEST_CONTAINER_RUN_EXTRA_ARGS="$OP_TEST_CONTAINER_RUN_EXTRA_ARGS -v $p:/tmp/community-operators-for-catalog"
fi

OP_TEST_CHECK_STEAM_OK=0
[ "$OP_TEST_STREAM" = "." ] && [ "$OP_TEST_VERSION" = "sync" ] && OP_TEST_STREAM=$OP_TEST_OPERATOR && OP_TEST_OPERATOR=$OP_TEST_VERSION
[ "$OP_TEST_STREAM" = "community-operators" ] && OP_TEST_CHECK_STEAM_OK=1
[ "$OP_TEST_STREAM" = "upstream-community-operators" ] && OP_TEST_CHECK_STEAM_OK=1

[[ $OP_TEST_CHECK_STEAM_OK -eq 0 ]] && { echo "Error : Unknwn value for 'OP_TEST_STREAM=$OP_TEST_STREAM' !!!"; exit 1; }

function ExecParameters() {
    OP_TEST_EXEC_USER=
    OP_TEST_EXEC_USER_SECRETS=
    OP_TEST_EXEC_USER_INDEX_CHECK=
    OP_TEST_SKIP=0
    [[ $1 == kiwi* ]] && OP_TEST_EXEC_USER="-e operator_dir=$OP_TEST_BASE_DIR/$OP_TEST_STREAM/$OP_TEST_OPERATOR -e operator_version=$OP_TEST_VERSION --tags pure_test"
    [[ $1 == kiwi* ]] && [ "$OP_TEST_STREAM" = "community-operators" ] && [[ $OP_TEST_FORCE_DEPLOY_ON_K8S -eq 0 ]] && OP_TEST_EXEC_USER="$OP_TEST_EXEC_USER -e test_skip_deploy=true"
    [[ $1 == lemon* ]] && OP_TEST_EXEC_USER="-e operator_dir=$OP_TEST_BASE_DIR/$OP_TEST_STREAM/$OP_TEST_OPERATOR --tags deploy_bundles"
    [[ $1 == orange* ]] && [ "$OP_TEST_VERSION" != "sync" ] && OP_TEST_EXEC_USER="-e operator_dir=$OP_TEST_BASE_DIR/$OP_TEST_STREAM/$OP_TEST_OPERATOR $PROD_REGISTRY_ARGS --tags deploy_bundles"

    # [[ $1 == orange* ]] &&  [ "$OP_TEST_VERSION" = "sync" ] && OP_TEST_EXEC_USER="-e operators_config=$OP_TEST_BASE_DIR/$OP_TEST_STREAM/$OP_TEST_OPERATOR $PROD_REGISTRY_ARGS --tags deploy_bundles"
    [[ $1 == orange* ]] &&  [ "$OP_TEST_VERSION" = "sync" ] && OP_TEST_EXEC_USER="--tags deploy_bundles"


    [[ $1 == orange* ]] && [ "$OP_TEST_STREAM" = "community-operators" ] && OP_TEST_EXEC_USER="$OP_TEST_EXEC_USER -e production_registry_namespace=quay.io/openshift-community-operators"
    [[ $1 == orange* ]] && [ "$OP_TEST_STREAM" = "upstream-community-operators" ] && OP_TEST_EXEC_USER="$OP_TEST_EXEC_USER -e production_registry_namespace=quay.io/operatorhubio"


    # Handle index_check
    [ "$OP_TEST_STREAM" = "community-operators" ] && OP_TEST_EXEC_USER_INDEX_CHECK="-e run_prepare_catalog_repo_upstream=true -e bundle_index_image=quay.io/openshift-community-operators/catalog:latest -e operator_base_dir=$OP_TEST_BASE_DIR/$OP_TEST_STREAM"
    [[ $1 == orange_* ]] && [ "$OP_TEST_STREAM" = "community-operators" ] && OP_TEST_EXEC_USER_INDEX_CHECK="-e run_prepare_catalog_repo_upstream=true -e bundle_index_image=quay.io/openshift-community-operators/catalog:${1/orange_/} -e operator_base_dir=$OP_TEST_BASE_DIR/$OP_TEST_STREAM"
    [ "$OP_TEST_STREAM" = "upstream-community-operators" ] && OP_TEST_EXEC_USER_INDEX_CHECK="-e run_prepare_catalog_repo_upstream=true -e bundle_index_image=quay.io/operatorhubio/catalog:latest -e operator_base_dir=$OP_TEST_BASE_DIR/$OP_TEST_STREAM"
    # [ "$OP_TEST_STREAM" = "upstream-community-operators" ] && [[ $OP_TEST_PROD -eq 2 ]] && OP_TEST_EXEC_USER_INDEX_CHECK="-e run_prepare_catalog_repo_upstream=true -e bundle_index_image=quay.io/operator_testing/catalog:latest -e operator_base_dir=$OP_TEST_BASE_DIR/$OP_TEST_STREAM"


    [[ $1 == orange* ]] && [[ $OP_TEST_PROD -eq 1 ]] && [ "$OP_TEST_STREAM" = "community-operators" ] && OP_TEST_EXEC_USER="$OP_TEST_EXEC_USER -e bundle_registry=quay.io -e bundle_image_namespace=openshift-community-operators -e bundle_index_image_namespace=openshift-community-operators -e bundle_index_image_namespace=openshift-community-operators -e bundle_index_image_name=catalog"
    [[ $1 == orange* ]] && [[ $OP_TEST_PROD -eq 1 ]] && [ "$OP_TEST_STREAM" = "community-operators" ] && OP_TEST_EXEC_USER_SECRETS="$OP_TEST_EXEC_USER_SECRETS -e quay_api_token=$QUAY_API_TOKEN_OPENSHIFT_COMMUNITY_OP"
    [[ $1 == orange* ]] && [[ $OP_TEST_PROD -eq 1 ]] && [ "$OP_TEST_STREAM" = "upstream-community-operators" ] && OP_TEST_EXEC_USER="$OP_TEST_EXEC_USER -e bundle_registry=quay.io -e bundle_image_namespace=operatorhubio -e bundle_index_image_namespace=operatorhubio -e bundle_index_image_name=catalog"
    [[ $1 == orange* ]] && [[ $OP_TEST_PROD -eq 1 ]] && [ "$OP_TEST_STREAM" = "upstream-community-operators" ] && OP_TEST_EXEC_USER_SECRETS="$OP_TEST_EXEC_USER_SECRETS -e quay_api_token=$QUAY_API_TOKEN_OPERATORHUBIO"

    # Only for testing use case
    [[ $1 == orange* ]] && [[ $OP_TEST_PROD -eq 2 ]] && OP_TEST_EXEC_USER="$OP_TEST_EXEC_USER -e bundle_registry=quay.io -e bundle_image_namespace=operator_testing -e bundle_index_image_namespace=operator_testing -e bundle_index_image_name=catalog"
    [[ $1 == orange* ]] && [[ $OP_TEST_PROD -eq 2 ]] && OP_TEST_EXEC_USER_SECRETS="$OP_TEST_EXEC_USER_SECRETS -e quay_api_token=$QUAY_API_TOKEN_OPERATOR_TESTING"


    # If community and doing orange_<version>
    [[ $1 == orange_* ]] && [ "$OP_TEST_STREAM" = "community-operators" ] && OP_TEST_EXEC_USER="$OP_TEST_EXEC_USER -e use_cluster_filter=true -e supported_cluster_versions_in=${1/orange_/}"

    # Failing test when upstream and orgage_<version> (not supported yet)
    [[ $1 == orange_* ]] && [ "$OP_TEST_STREAM" = "upstream-community-operators" ] && OP_TEST_EXEC_USER=""

    # Don't reset kind when production (It should speedup deploy when kind and registry is not needed)
    [[ $1 == orange* ]] && [[ $OP_TEST_PROD -ge 1 ]] && OP_TEST_RESET=0

    [[ $OP_TEST_VER_OVERWRITE -eq 1 ]] && [ -z $OP_TEST_VERSION ] && { echo "Warning: OP_TEST_VER_OVERWRITE=1 and no version specified 'OP_TEST_VERSION=$OP_TEST_VERSION' !!! Skipping ..."; OP_TEST_SKIP=1; }


    # Handle index_check
    # [ "$OP_TEST_STREAM" = "community-operators" ] && OP_TEST_EXEC_USER_INDEX_CHECK="-e run_prepare_catalog_repo_upstream=false -e bundle_registry=quay.io -e bundle_index_image_namespace=openshift-community-operators -e bundle_index_image_name=catalog -e operator_base_dir=$OP_TEST_BASE_DIR/$OP_TEST_STREAM"
    # [ "$OP_TEST_STREAM" = "upstream-community-operators" ] && OP_TEST_EXEC_USER_INDEX_CHECK="-e run_prepare_catalog_repo_upstream=false -e bundle_registry=quay.io -e bundle_image_namespace=operatorhubio -e bundle_index_image_name=catalog -e operator_base_dir=$OP_TEST_BASE_DIR/$OP_TEST_STREAM"

    # [[ $1 == orange_* ]] && [ "$OP_TEST_STREAM" = "community-operators" ] && OP_TEST_EXEC_USER_INDEX_CHECK="$OP_TEST_EXEC_USER_INDEX_CHECK -e bundle_index_image_version=${1/orange_/}"

    # Handle OP_TEST_VER_OVERWRITE
    [[ $1 == orange* ]] && [[ $OP_TEST_VER_OVERWRITE -eq 0 ]] && OP_TEST_EXEC_USER="$OP_TEST_EXEC_USER -e fail_on_no_index_change=true"
    [[ $1 == orange* ]] && [[ $OP_TEST_VER_OVERWRITE -eq 1 ]] && [ "$OP_TEST_VERSION" != "sync" ] && OP_TEST_EXEC_USER="$OP_TEST_EXEC_USER -e operator_version=$OP_TEST_VERSION -e bundle_force_rebuild=true -e fail_on_no_index_change=false -e index_force_update=true"

    # Handle OP_TEST_RECREATE
    # Handle OP_DELETE

    # Handle ci.yaml only chnage


    # -e index_force_update=true -e strict_mode=true : to orange prod


# bundle_index_image_version
    # TODO redhat mirror
    #"-e mirror_index_images=quay.io/redhat/redhat----community-operator-index|redhat+iib_community|$QUAY_RH_INDEX_PW"
}

echo "Using $(ansible --version | head -n 1) ..."
if [[ $OP_TEST_DEBUG -ge 2 ]];then
    run echo "OP_TEST_DEBUG='$OP_TEST_DEBUG'"
    run echo "OP_TEST_DRY_RUN='$OP_TEST_DRY_RUN'"
    run echo "OP_TEST_EXEC_USER='$OP_TEST_EXEC_USER'"
    run echo "OP_TEST_IMAGE='$OP_TEST_IMAGE'"
    run echo "OP_TEST_CONTAINER_EXEC_EXTRA_ARGS='$OP_TEST_CONTAINER_EXEC_EXTRA_ARGS'"
    run echo "OP_TEST_CERT_DIR='$OP_TEST_CERT_DIR'"
    run echo "OP_TEST_CONTAINER_TOOL='$OP_TEST_CONTAINER_TOOL'"
    run echo "OP_TEST_NAME='$OP_TEST_NAME'"
    run echo "OP_TEST_ANSIBLE_PULL_REPO='$OP_TEST_ANSIBLE_PULL_REPO'"
    run echo "OP_TEST_ANSIBLE_PULL_BRANCH='$OP_TEST_ANSIBLE_PULL_BRANCH'"
    run echo "OP_TEST_ANSIBLE_DEFAULT_ARGS='$OP_TEST_ANSIBLE_DEFAULT_ARGS'"
    run echo "OP_TEST_ANSIBLE_EXTRA_ARGS='$OP_TEST_ANSIBLE_EXTRA_ARGS'"
    run echo "OP_TEST_CONAINER_RUN_DEFAULT_ARGS='$OP_TEST_CONTAINER_RUN_EXTRA_ARGS'"
    run echo "OP_TEST_CONTAINER_RUN_EXTRA_ARGS='$OP_TEST_CONTAINER_RUN_EXTRA_ARGS'"
    run echo "OP_TEST_CONTAINER_EXEC_DEFAULT_ARGS='$OP_TEST_CONTAINER_EXEC_EXTRA_ARGS'"
    run echo "OP_TEST_CONTAINER_EXEC_EXTRA_ARGS='$OP_TEST_CONTAINER_EXEC_EXTRA_ARGS'"
    run echo "OP_TEST_RUN_MODE='$OP_TEST_RUN_MODE'"
    run echo "OP_TEST_FORCE_INSTALL='$OP_TEST_FORCE_INSTALL'"
    run echo "OP_TEST_LOG_DIR='$OP_TEST_LOG_DIR'"
fi

echo -e "\nOne can do 'tail -f $OP_TEST_LOG_DIR/log.out' from second console to see full logs\n"


# Check if kind is installed
echo -e "Checking for kind binary ..."
if ! $DRY_RUN_CMD command -v kind > /dev/null 2>&1; then
    OP_TEST_FORCE_INSTALL=1
# else
#     echo -e "Testing existance of kind cluster ..."
#     # Check if kind cluster is running
#     if ! $DRY_RUN_CMD kind get clusters | grep operator-test > /dev/null 2>&1; then
#         OP_TEST_FORCE_INSTALL=1
#         echo
#     fi
fi

# Install prerequisites (kind cluster)
[[ $OP_TEST_FORCE_INSTALL -eq 1 ]] && run echo -e " [ Installing prerequisites ] "
[[ $OP_TEST_FORCE_INSTALL -eq 1 ]] && run $DRY_RUN_CMD ansible-pull -U $OP_TEST_ANSIBLE_PULL_REPO -C $OP_TEST_ANSIBLE_PULL_BRANCH $OP_TEST_ANSIBLE_DEFAULT_ARGS $OP_TEST_ANSIBLE_EXTRA_ARGS -e run_prepare_catalog_repo_upstream=false

if [ -n "$OP_TEST_REPO" ];then
    OP_TEST_EXEC_EXTRA="$OP_TEST_EXEC_EXTRA -e catalog_repo=$OP_TEST_REPO -e catalog_repo_branch=$OP_TEST_BRANCH"
else
    OP_TEST_EXEC_EXTRA="$OP_TEST_EXEC_EXTRA -e run_prepare_catalog_repo_upstream=false"
fi
# Start container
echo -e " [ Preparing testing container '$OP_TEST_NAME' from '$OP_TEST_IMAGE' ] "
$DRY_RUN_CMD $OP_TEST_CONTAINER_TOOL pull $OP_TEST_IMAGE > /dev/null 2>&1 || { echo "Error: Problem pulling image '$OP_TEST_IMAGE' !!!"; exit 1; }

OP_TEST_CONTAINER_OPT="$OP_TEST_CONTAINER_OPT -e ANSIBLE_CONFIG=/playbooks/upstream/ansible.cfg"
OP_TEST_SKIP=0
for t in $TESTS;do

    ExecParameters $t
    [[ $OP_TEST_SKIP -eq 1 ]] && echo "Skipping test '$t' for '$OP_TEST_STREAM $OP_TEST_OPERATOR $OP_TEST_VERSION' ..." && continue

    [ -z "$OP_TEST_EXEC_USER" ] && { echo "Error: Unknown test '$t' for '$OP_TEST_STREAM $OP_TEST_OPERATOR $OP_TEST_VERSION' !!! Exiting ..."; help; }
    echo -e "Test '$t' for '$OP_TEST_STREAM $OP_TEST_OPERATOR $OP_TEST_VERSION' ..."
    if [[ $OP_TEST_RESET -eq 1 ]];then
        echo -e "[$t] Reseting kind cluster ..."
        run $DRY_RUN_CMD ansible-pull -U $OP_TEST_ANSIBLE_PULL_REPO -C $OP_TEST_ANSIBLE_PULL_BRANCH $OP_TEST_ANSIBLE_DEFAULT_ARGS --tags reset
    fi
    OP_TEST_KUBECONFIG=$()
    echo -e "[$t] Running test ..."
    [[ $OP_TEST_DEBUG -ge 3 ]] && echo "OP_TEST_EXEC_EXTRA=$OP_TEST_EXEC_EXTRA"
    $DRY_RUN_CMD $OP_TEST_CONTAINER_TOOL rm -f $OP_TEST_NAME > /dev/null 2>&1
    run $DRY_RUN_CMD $OP_TEST_CONTAINER_TOOL run -d --rm $OP_TEST_CONTAINER_OPT --name $OP_TEST_NAME $OP_TEST_CONAINER_RUN_DEFAULT_ARGS $OP_TEST_CONTAINER_RUN_EXTRA_ARGS $OP_TEST_IMAGE
    run $DRY_RUN_CMD $OP_TEST_CONTAINER_TOOL cp $HOME/.kube $OP_TEST_NAME:/root/
    set -e
    if [[ $1 == orange* ]] && [[ $OP_TEST_PROD -ge 1 ]] && [ "$OP_TEST_VERSION" = "sync" ];then
        echo "$OP_TEST_EXEC_BASE $OP_TEST_EXEC_EXTRA --tags index_check $OP_TEST_EXEC_USER_INDEX_CHECK"
        run $DRY_RUN_CMD $OP_TEST_CONTAINER_TOOL exec $OP_TEST_CONTAINER_OPT $OP_TEST_NAME /bin/bash -c "update-ca-trust && $OP_TEST_EXEC_BASE $OP_TEST_EXEC_EXTRA --tags index_check $OP_TEST_EXEC_USER_INDEX_CHECK"
        set +e
        run $DRY_RUN_CMD $OP_TEST_CONTAINER_TOOL exec $OP_TEST_CONTAINER_OPT $OP_TEST_NAME /bin/bash -c "ls $OP_TEST_UNCOMPLETE" || continue
        set -e
        OP_TEST_EXEC_USER="$OP_TEST_EXEC_USER -e operators_config=$OP_TEST_UNCOMPLETE"
    fi
    echo "$OP_TEST_EXEC_BASE $OP_TEST_EXEC_EXTRA $OP_TEST_EXEC_USER"
    run $DRY_RUN_CMD $OP_TEST_CONTAINER_TOOL exec $OP_TEST_CONTAINER_OPT $OP_TEST_NAME /bin/bash -c "update-ca-trust && $OP_TEST_EXEC_BASE $OP_TEST_EXEC_EXTRA $OP_TEST_EXEC_USER $OP_TEST_EXEC_USER_SECRETS"
    set +e
    echo -e "Test '$t' : [ OK ]\n"
done

echo "Done"

# For playbook developers
# export OP_TEST_ANSIBLE_PULL_REPO="https://github.com/J0zi/operator-test-playbooks"
# OP_TEST_DEBUG=1 OP_TEST_ANSIBLE_PULL_REPO="https://github.com/J0zi/operator-test-playbooks" bash <(curl -s https://raw.githubusercontent.com/J0zi/operator-test-playbooks/upstream-community/test/test.sh)
# export CURLOPT_FRESH_CONNECT=true
