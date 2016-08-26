#!/bin/bash
#
# # Usage
#
# ```
# $ hab-pkg-dockerize [PKG ...]
# ```
#
# # Synopsis
#
# Create a Docker container from a set of Habitat packages.
#
# # License and Copyright
#
# ```
# Copyright: Copyright (c) 2016 Chef Software, Inc.
# License: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# ```

# Fail if there are any unset variables and whenever a command returns a
# non-zero exit code.
set -eu

# If the variable `$DEBUG` is set, then print the shell commands as we execute.
if [ -n "${DEBUG:-}" ]; then
  set -x
  export DEBUG
fi

# ## Help

# **Internal** Prints help
print_help() {
  printf -- "$program $version

$author

Habitat Package Dockerize - Create a Docker container from a set of Habitat packages

USAGE:
  $program [PKG ..]
"
}

# **Internal** Exit the program with an error message and a status code.
#
# ```sh
# exit_with "Something bad went down" 55
# ```
exit_with() {
  case "${TERM:-}" in
    *term | xterm-* | rxvt | screen | screen-*)
      printf -- "\033[1;31mERROR: \033[1;37m$1\033[0m\n"
      ;;
    *)
      printf -- "ERROR: $1\n"
      ;;
  esac
  exit $2
}

find_system_commands() {
  if $(mktemp --version 2>&1 | grep -q 'GNU coreutils'); then
    _mktemp_cmd=$(command -v mktemp)
  else
    if $(/bin/mktemp --version 2>&1 | grep -q 'GNU coreutils'); then
      _mktemp_cmd=/bin/mktemp
    else
      exit_with "We require GNU mktemp to build docker images; aborting" 1
    fi
  fi
}

# Wraps `dockerfile` to ensure that a Docker image build is being executed in a
# clean directory with native filesystem permissions which is outside the
# source code tree.
build_docker_image() {
  local ident_file="$(hab pkg path $1)/IDENT"
  if [[ ! -f "$ident_file" ]]; then
    hab pkg install $1 # try to install it
  fi

  pkg_name=$(package_name_for $1)
  pkg_origin=$(package_origin_for $ident_file)
  pkg_ident=$(package_ident_for $ident_file)
  pkg_version=$(version_num_for $ident_file)

  BASE_PKGS=$(base_pkgs $@)
  DOCKER_BASE_TAG="${pkg_ident}_base:$(base_pkg_hash $BASE_PKGS)"
  DOCKER_BASE_TAG_ALT="${pkg_origin}/habitat_export_base:$(base_pkg_hash $BASE_PKGS)"

  # create base layer image
  DOCKER_CONTEXT="$($_mktemp_cmd -t -d "${program}-XXXX")"
  pushd $DOCKER_CONTEXT > /dev/null
  docker_base_image $@
  popd > /dev/null
  rm -rf "$DOCKER_CONTEXT"

  # build runtime image
  DOCKER_CONTEXT="$($_mktemp_cmd -t -d "${program}-XXXX")"
  pushd $DOCKER_CONTEXT > /dev/null
  docker_image $@
  popd > /dev/null
  rm -rf "$DOCKER_CONTEXT"
}

# pkg_origin: core
package_origin_for() {
  local ident_file="$1"
  cat $ident_file | awk 'BEGIN { FS = "/" }; { print $1 }'
}

# pkg_ident: core/gzip
package_ident_for() {
  local ident_file="$1"
  cat $ident_file | awk 'BEGIN { FS = "/" }; { print $1 "/" $2 }'
}

# pkg_name: gzip
package_name_for() {
  local pkg="$1"
  echo $(echo $pkg | cut -d "/" -f 2)
}

package_exposes() {
  local pkg="$1"
  local expose_file="$(hab pkg path $pkg)/EXPOSES"
  if [ -f "$expose_file" ]; then
    cat $expose_file
  fi
}

# version_tag: 1.6-20160729193649
version_num_for() {
  local ident_file="$1"
  cat $ident_file | awk 'BEGIN { FS = "/" }; { print $3 "-" $4 }'
}

# Collect all dependencies for requested packages
base_pkgs() {
  local BUILD_PKGS="$@"
  for p in $BUILD_PKGS; do
    hab pkg install $p >/dev/null
    cat $(hab pkg path $p)/DEPS >> /tmp/_all_deps
  done
  (cat /tmp/_all_deps | sort | uniq) && rm -f /tmp/_all_deps
}

base_pkg_hash() {
  echo "$@" | sha256sum | cut -b1-16
}

docker_base_image() {

  if [[ -n "$(docker images -q $DOCKER_BASE_TAG 2> /dev/null)" ]]; then
    # image already exists
    echo "base docker image $DOCKER_BASE_TAG already built; skipping rebuild"
    return 0;
  fi

  if [[ -n "$(docker images -q $DOCKER_BASE_TAG_ALT 2> /dev/null)" ]]; then
    # image already exists
    echo "base docker image $DOCKER_BASE_TAG_ALT already built; skipping rebuild"
    # create a tag alias for our package
    docker tag $DOCKER_BASE_TAG_ALT $DOCKER_BASE_TAG
    DOCKER_BASE_TAG="$DOCKER_BASE_TAG_ALT"
    return 0;
  fi

  env PKGS="$BASE_PKGS" NO_MOUNT=1 hab-studio -r $DOCKER_CONTEXT/rootfs -t baseimage new
  echo "$1" > $DOCKER_CONTEXT/rootfs/.hab_pkg

  # create base image Dockerfile
  cat <<EOT > $DOCKER_CONTEXT/Dockerfile
FROM scratch
ENV $(cat $DOCKER_CONTEXT/rootfs/init.sh | grep PATH= | cut -d' ' -f2-)
WORKDIR /
ADD rootfs /
EOT

  docker build --force-rm --no-cache -t $DOCKER_BASE_TAG .
  docker tag $DOCKER_BASE_TAG $DOCKER_BASE_TAG_ALT
}

docker_image() {
  local version_tag="${pkg_ident}:${pkg_version}"
  local latest_tag="${pkg_ident}:latest"

  local pkg_file=$(ls /hab/cache/artifacts/$(cat $(hab pkg path $pkg_ident)/IDENT | tr '/' '-')-*)
  cp -a $pkg_file $DOCKER_CONTEXT/
  pkg_file=$(basename $pkg_file)

  cat <<EOT > $DOCKER_CONTEXT/Dockerfile
FROM ${DOCKER_BASE_TAG}
COPY ${pkg_file} /tmp/
RUN hab pkg install /tmp/${pkg_file} && rm -f /tmp/${pkg_file}
VOLUME $HAB_ROOT_PATH/svc/${pkg_name}/data $HAB_ROOT_PATH/svc/${pkg_name}/config
EXPOSE 9631 $(package_exposes $1)
ENTRYPOINT ["/init.sh"]
CMD ["start", "$1"]
EOT

  docker build --force-rm --no-cache -t $version_tag .
  docker tag $version_tag $latest_tag
}

# The root of the filesystem. If the program is running on a seperate
# filesystem or chroot environment, this environment variable may need to be
# set.
: ${FS_ROOT:=}
# The root path of the Habitat file system. If the `$HAB_ROOT_PATH` environment
# variable is set, this value is overridden, otherwise it is set to its default
: ${HAB_ROOT_PATH:=$FS_ROOT/hab}

# The current version of Habitat Studio
version='@version@'
# The author of this program
author='@author@'
# The short version of the program name which is used in logging output
program=$(basename $0)

find_system_commands

if [ -z "$@" ]; then
  print_help
  exit_with "You must specify one or more Habitat packages to Dockerize." 1
elif [ "$@" == "--help" ]; then
  print_help
else
  build_docker_image $@
fi
