#!/usr/bin/env bash

# "To provide additional docker-compose args, set the COMPOSE var. Ex:
# COMPOSE="-f FILE_PATH_HERE"

set -ux
set -o errexit
set -o pipefail
set -o nounset
# set -o xtrace

ERROR() {
    /bin/echo -e "\e[101m\e[97m[ERROR]\e[49m\e[39m" "$@"
}

WARNING() {
    /bin/echo -e "\e[101m\e[97m[WARNING]\e[49m\e[39m" "$@"
}

INFO() {
    /bin/echo -e "\e[104m\e[97m[INFO]\e[49m\e[39m" "$@"
}

exists() {
    type "$1" > /dev/null 2>&1
}

TIOPS_ROOT=${TIOPS_ROOT:-""}

# Change directory to the source directory of this script. Taken from:
# https://stackoverflow.com/a/246128/3858681
pushd "$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

HELP=0
INIT_ONLY=0
DEV=""
COMPOSE=${COMPOSE:-""}
RUN_AS_DAEMON=0
POSITIONAL=()

while [[ $# -gt 0 ]]
do
    key="$1"

    case $key in
        --help)
            HELP=1
            shift # past argument
            ;;
        --init-only)
            INIT_ONLY=1
            shift # past argument
            ;;
        --dev)
            if [ ! "$TIOPS_ROOT" ]; then
                TIOPS_ROOT="$(cd ../ && pwd)"
                INFO "TIOPS_ROOT is not set, defaulting to: $TIOPS_ROOT"
            fi
            INFO "Running docker-compose with dev config"
            DEV="-f docker-compose.dev.yml"
            shift # past argument
            ;;
        --compose)
            COMPOSE="-f $2"
            shift # past argument
            shift # past value
            ;;
        -d|--daemon)
            INFO "Running docker-compose as daemon"
            RUN_AS_DAEMON=1
            shift # past argument
            ;;
        *)
            POSITIONAL+=("$1")
            ERROR "unknown option $1"
            shift # past argument
            ;;
    esac
done

# comment because ERROR:
# ./up.sh: line 79: POSITIONAL[@]: unbound variable]
# set -- "${POSITIONAL[@]}" # restore positional parameters

if [ "${HELP}" -eq 1 ]; then
    echo "Usage: $0 [OPTION]"
    echo "  --help                                                Display this message"
    echo "  --init-only                                           Initializes ssh-keys, but does not call docker-compose"
    echo "  --daemon                                              Runs docker-compose in the background"
    echo "  --dev                                                 Mounts dir at host's TIOPS_ROOT to /tiops on tiops-control container, syncing files for development"
    echo "  --compose PATH                                        Path to an additional docker-compose yml config."
    echo "To provide multiple additional docker-compose args, set the COMPOSE var directly, with the -f flag. Ex: COMPOSE=\"-f FILE_PATH_HERE -f ANOTHER_PATH\" ./up.sh --dev"
    exit 0
fi

exists ssh-keygen || { ERROR "Please install ssh-keygen (apt-get install openssh-client)"; exit 1; }
exists perl || { ERROR "Please install perl (apt-get install perl)"; exit 1; }

# Generate SSH keys for the control node
if [ ! -f ./secret/node.env ]; then
    INFO "Generating key pair"
    mkdir -p secret
    ssh-keygen -t rsa -N "" -f ./secret/id_rsa

    INFO "Generating ./secret/control.env"
    { echo "# generated by tiops/docker/up.sh, parsed by tiops/docker/control/bashrc";
      echo "# NOTE: newline is expressed as ↩";
      echo "SSH_PRIVATE_KEY=$(perl -p -e "s/\n/↩/g" < ./secret/id_rsa)";
      echo "SSH_PUBLIC_KEY=$(cat ./secret/id_rsa.pub)"; } >> ./secret/control.env

    INFO "Generating ./secret/node.env"
    { echo "# generated by tiops/docker/up.sh, parsed by the \"tutum/debian\" docker image entrypoint script";
      echo "ROOT_PASS=root";
      echo "AUTHORIZED_KEYS=$(cat ./secret/id_rsa.pub)"; } >> ./secret/node.env
else
    INFO "No need to generate key pair"
fi

# Make sure folders referenced in control Dockerfile exist and don't contain leftover files
rm -rf ./control/tiops
mkdir -p ./control/tiops/tiops
# Copy the tiops directory if we're not mounting the TIOPS_ROOT
if [ -z "${DEV}" ]; then
    # Dockerfile does not allow `ADD ..`. So we need to copy it here in setup.
    INFO "Copying .. to control/tiops"
    (
		# TODO support exclude-ignore, check version of tar support this.
		# https://www.gnu.org/software/tar/manual/html_section/tar_48.html#IDX408
        # (cd ..; tar --exclude=./docker --exclude=./.git --exclude-ignore=.gitignore -cf - .)  | tar Cxf ./control/tiops -
        (cd ..; tar --exclude=./docker --exclude=./.git -cf - .)  | tar Cxf ./control/tiops -
    )
else
	INFO "Build tiops in $TIOPS_ROOT"
	(cd $TIOPS_ROOT;GOOS=linux GOARCH=amd64 make build)
fi

if [ "${INIT_ONLY}" -eq 1 ]; then
    exit 0
fi

exists docker ||
    { ERROR "Please install docker (https://docs.docker.com/engine/installation/)";
      exit 1; }
exists docker-compose ||
    { ERROR "Please install docker-compose (https://docs.docker.com/compose/install/)";
      exit 1; }

INFO "Running \`docker-compose build\`"
# shellcheck disable=SC2086
docker-compose -f docker-compose.yml ${COMPOSE} ${DEV} build

docker network create --gateway 172.19.0.1 --subnet 172.19.0.0/16 tiops > /dev/null 2>&1 || echo "Skip create tiops network"

INFO "Running \`docker-compose up\`"
if [ "${RUN_AS_DAEMON}" -eq 1 ]; then
    # shellcheck disable=SC2086
    docker-compose -f docker-compose.yml ${COMPOSE} ${DEV} up -d
    INFO "All containers started, run \`docker ps\` to view"
else
    INFO "Please run \`docker exec -it tiops-control bash\` in another terminal to proceed"
    # shellcheck disable=SC2086
    docker-compose -f docker-compose.yml ${COMPOSE} ${DEV} up
fi

popd
