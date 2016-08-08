#!/bin/bash

if [[ ${DEBUG} ]]; then
  set -x
fi

cleanup() {
  set +x
}

trap cleanup EXIT

# Requires `curl`, `basename` and `jq` to function

__config_file_dir="${HOME}/.vmpooler"
__config_file="${__config_file_dir}/config.json"
__lease_dir="${__config_file_dir}/leases"

# Respect these environment variables
VMPOOLER_TOKEN="${VMPOOLER_TOKEN:-UNDEFINED}"
VMPOOLER_URL="${VMPOOLER_URL:-UNDEFINED}"
VMPOOLER_SSH_KEY="${VMPOOLER_SSH_KEY:-UNDEFINED}"
VMPOOLER_SSH_OPTIONS="${VMPOOLER_SSH_OPTIONS:-UNDEFINED}"

# Create a lease directory
mkdir -p "${__lease_dir}"

### Utilities

echo_downcase(){
  local arg="${1:-UNDEFINED}"

  if [[ ${arg} == UNDEFINED ]]; then
    echo "please provide a string to convert to lowercase" >&2
    return 1
  fi

  echo "${arg}" | tr '[:upper:]' '[:lower:]'
  return $?
}

echo_map_legacy_name(){
  local platform="${1:-UNDEFINED}"

  if [[ ${platform} == UNDEFINED ]]; then
    echo "please provide a platform name" >&2
    return 1
  fi

  if [[ ${platform} =~ -amd64$ ]]; then
    # We're using sed instead of string substitution because the
    # regex should be anchored for predictability.
    # shellcheck disable=SC2001
    echo "${platform}" | sed -e 's/-amd64$/-x86_64/g'
  fi
  return $?
}

echo_parse_vm_hostname() {
  local json="${1:-UNDEFINED}"
  local platform_tag="${2:-UNDEFINED}"

  if [[ ${json} == UNDEFINED ]]; then
    echo "please provide JSON output to parse" >&2
    return 1
  fi

  if [[ ${platform_tag} == UNDEFINED ]]; then
    echo "please provide a platform tag" >&2
    return 1
  fi

  echo "${json[@]}" | jq --exit-status --raw-output  ".[] | .. | .hostname? | select(. == null | not)"
  return $?
}

echo_parse_vm_domainname() {
  local json="${1:-UNDEFINED}"

  if [[ ${json} == UNDEFINED ]]; then
    echo "please provide JSON output to parse" >&2
    return 1
  fi

  echo "${json[@]}" | jq --exit-status --raw-output  ".domain | select(. == null | not)"
  return $?
}

echo_parse_vm_pooler_token() {
  local json="${1:-UNDEFINED}"
  local token

  if [[ ${json} == UNDEFINED ]]; then
    echo "please provide JSON output to parse" >&2
    return 1
  fi

  echo "${json[@]}" | jq --exit-status --raw-output  ".token | select(. == null | not)"
  return $?
}

echo_lease_path() {
  local lease="${1:-UNDEFINED}"

  if [[ ${lease} == UNDEFINED ]]; then
    echo "please provide a lease name to lookup" >&2
    return 1
  fi

  if [ ! -d "${__lease_dir}" ]; then
    echo "cannot find directory to read leases from" >&2
    return 1
  fi

  echo "${__lease_dir}/${lease}"
  return $?
}

parse_config() {
  if [[ ! -f ${__config_file} ]]; then
    echo "cannot find config file ${__config_file}; unable to parse a nonexistant or unreadable file" >&2
    return 1
  fi

  if [[ ${VMPOOLER_TOKEN} == UNDEFINED ]]; then
    VMPOOLER_TOKEN="$(jq --exit-status --raw-output ".vmpooler_token // empty"  "${__config_file}")"
  else
    echo -e "- using environment variable VMPOOLER_TOKEN for access token\n"
  fi

  if [[ ${VMPOOLER_URL} == UNDEFINED ]]; then
    VMPOOLER_URL="$(jq --exit-status --raw-output ".vmpooler_url // empty"  "${__config_file}")"
  else
    echo -e "- using environment variable VMPOOLER_URL to connect to VM Pooler API\n"
  fi

  if [[ ${VMPOOLER_SSH_KEY} == UNDEFINED ]]; then
    VMPOOLER_SSH_KEY="$(jq --exit-status --raw-output ".vmpooler_ssh_key // empty"  "${__config_file}")"
  else
    echo -e "- using environment variable VMPOOLER_SSH_KEY to connect to leased clients\n"
  fi

  if [[ ${VMPOOLER_SSH_OPTIONS} == UNDEFINED ]]; then
    VMPOOLER_SSH_OPTIONS="$(jq --exit-status --raw-output ".vmpooler_ssh_options // empty"  "${__config_file}")"
  else
    echo -e "- using environment variable VMPOOLER_SSH_OPTIONS to connect to leased clients\n"
  fi

  return $?
}

print_config(){
  [[ -n "${VMPOOLER_TOKEN}" ]] &&
    echo "VMPOOLER_TOKEN: ${VMPOOLER_TOKEN}" ||
    echo "VMPOOLER_TOKEN: undefined - use an environment variable?"

  [[ -n "${VMPOOLER_URL}" ]] &&
    echo "VMPOOLER_URL: ${VMPOOLER_URL}" ||
    echo "VMPOOLER_URL: undefined - use an environment variable?"

  [[ -n "${VMPOOLER_SSH_KEY}" ]] &&
    echo "VMPOOLER_SSH_KEY: ${VMPOOLER_SSH_KEY}" ||
    echo "VMPOOLER_SSH_KEY: undefined - use an environment variable?"

  [[ -n "${VMPOOLER_SSH_OPTIONS}" ]] &&
    echo "VMPOOLER_SSH_OPTIONS: ${VMPOOLER_SSH_OPTIONS}" ||
    echo "VMPOOLER_SSH_OPTIONS: undefined - use an environment variable?"

  return $?
}

create_vm_lease() {
  local lease="${1:-UNDEFINED}"
  local lease_path

  if [[ ${lease} == UNDEFINED ]]; then
    echo "please provide a lease name to create" >&2
    return 1
  fi

  if [ ! -d "${__lease_dir}" ]; then
    echo "cannot find directory to write lease to" >&2
    return 1
  fi

  lease_path="$(echo_lease_path "${lease}")"
  if [ -e "${lease_path}" ]; then
    echo "lease '${lease}' already exists" >&2
    return 1
  fi

  touch "${lease_path}"
  return $?
}

write_vm_lease_details() {
  local vm_hostname="${1:-UNDEFINED}"
  local platform="${2:-UNDEFINED}"
  local domain="${3:-UNDEFINED}"
  local lease_path

  if [[ ${vm_hostname} == UNDEFINED ]]; then
    echo "please provide a VM hostname" >&2
    return 1
  fi

  if [[ ${platform} == UNDEFINED ]]; then
    echo "please provide a platform tag for $(basename "${vm_hostname}")" >&2
    return 1
  fi

  if [[ ${domain} == UNDEFINED ]]; then
    echo "please provide a DNS domain for $(basename "${vm_hostname}")" >&2
    return 1
  fi

  lease_path="$(echo_lease_path "${vm_hostname}")"

  if [[ ! -e "${lease_path}" ]]; then
    echo "lease '${lease}' does not exist; cannot write details to it" >&2
    return 1
  fi

  # Write out platform data to the lease
  echo "${platform_tag}" >> "${lease_path}"
  if [[ $? != 0 ]]; then
    echo "unable to write platform tag to lease" >&2
    return 1
  fi

  # Write out dns domain data to the lease
  echo "${domain}" >> "${lease_path}"
  if [[ $? != 0 ]]; then
    echo "unable to write dns domain to lease" >&2
    return 1
  fi
  return 0
}

write_vmpooler_token_to_file() {
  local token="${1:-UNDEFINED}"
  local new_config

  if [[ $token == UNDEFINED ]]; then
    echo "please provide a VM Pooler token" >&2
    return 1
  fi

  if [[ ! -w ${__config_file} ]]; then
    echo "cannot write to ${__config_file}" >&2
    return 1
  fi

  new_config="$(jq --exit-status --raw-output ". + { \"vmpooler_token\" : \"${token}\" }" "${__config_file}" 2>/dev/null)"
  if [[ $? != 0 ]]; then
    echo "unable to properly parse and update config file" >&2
  fi

  echo "${new_config}" > "${__config_file}"
  if [[ $? != 0 ]]; then
    echo "unable to write new VM Pooler token to config file" >&2
    return 1
  fi

  return 0
}

destroy_vm_lease() {
  local lease="${1:-UNDEFINED}"
  local lease_path

  if [[ ${lease} == UNDEFINED ]]; then
    echo "please provide a lease name to destroy" >&2
    return 1
  fi

  if [ ! -d "${__lease_dir}" ]; then
    echo "cannot find directory to remove lease from" >&2
    return 1
  fi

  lease_path="$(echo_lease_path "${lease}")"
  if [ ! -f "${lease_path}" ]; then
    echo "lease '${lease}' does not exist" >&2
    return 1
  fi

  echo "destroying lease ${lease}"
  rm -f "${lease_path}"
  return $?
}

test_vmpooler_token() {
  if [[ -z $VMPOOLER_TOKEN || $VMPOOLER_TOKEN == UNDEFINED ]]; then
    echo "no VM Pooler token found" >&2
    return 1
  fi
  return 0
}

### Pooler functions

vmpooler_checkout() {
  local platform_tag="${1:-UNDEFINED}"
  local json_output
  local vm_hostname
  local lease_path
  local domain

  if [[ ${platform_tag} == UNDEFINED ]]; then
    echo "please provide a platform tag to checkout" >&2
    return 1
  fi

  if ! test_vmpooler_token; then
    echo "cannot find VM Pooler token, cannot check out pooler VM"
    return 1
  fi

  json_output="$(curl --insecure --silent --request POST --header "X-AUTH-TOKEN:${VMPOOLER_TOKEN}" --url "${VMPOOLER_URL}/vm/${platform_tag}")"
  if [[ $? != 0 ]]; then
    echo "unable to check out instance of '${platform_tag}' host" >&2
    return 1
  fi

  vm_hostname="$(echo_parse_vm_hostname "${json_output}" "${platform_tag}")"
  if [[ $? != 0 ]]; then
    echo "unable to parse hostname for new instance of '${platform_tag}' host" >&2
    return 1
  fi

  domain="$(echo_parse_vm_domainname "${json_output}")"
  if [[ $? != 0 ]]; then
    echo "unable to parse dns domain for new instance of '${platform_tag}' host" >&2
    return 1
  fi

  # Save the VM Host details to a lease file
  echo "checked out ${vm_hostname} (${platform_tag})"
  create_vm_lease "${vm_hostname}"
  if [[ $? != 0 ]]; then
    echo "unable to write local lease for host '${vm_hostname}'" >&2
    return 1
  fi

  write_vm_lease_details "${vm_hostname}" "${platform_tag}" "${domain}"
  if [[ $? != 0 ]]; then
    echo "unable to write all VM Host lease details to lease file" >&2
    return 1
  fi

  return 0
}

vmpooler_destroy() {
  local vm_hostname="${1:-UNDEFINED}"
  local lease_path

  if [[ ${vm_hostname} == UNDEFINED ]]; then
    echo "please provide the name of a VM Pooler host to destroy" >&2
  fi

  if ! test_vmpooler_token; then
    echo "cannot find VM Pooler token, cannot destroy pooler VM"
    return 1
  fi

  curl \
    --insecure \
    --silent \
    --request DELETE \
    --header "X-AUTH-TOKEN:${VMPOOLER_TOKEN}" \
    --url "${VMPOOLER_URL}/vm/${vm_hostname}" &> /dev/null

  if [[ $? != 0 ]]; then
    echo "unable to confirm destruction of host '${vm_hostname}'" >&2
    return 1
  fi

  destroy_vm_lease "${vm_hostname}"
  if [[ $? != 0 ]]; then
    echo "unable to destroy lease for host '${vm_hostname}'" >&2
    return 1
  fi

  return 0
}

vmpooler_leases() {
  if [ ! -d "${__lease_dir}" ]; then
    echo "no lease directory found" >&2
    return 1
  fi

  while read -d $'\0' -r lease; do
    lease_name="$(basename "${lease}")"
    platform_tag="$(head -n1 "${lease}")"
    echo "${lease_name} (${platform_tag})"
  done < <(find "${__lease_dir}" -type f -print0)

  return 0
}

vmpooler_authorize() {
  local user="${1:-UNDEFINED}"
  local json_output
  local token

  if [[ ${user} == UNDEFINED ]]; then
    echo "please provide the LDAP name to request a token for" >&2
    return 1
  fi

  json_output="$(curl --silent --insecure --request POST --user "${user}" --url "${VMPOOLER_URL}/token")"
  if [[ $? != 0 ]]; then
    echo "unable to authorize '${user}' or retrieve a new token" >&2
    return 1
  fi

  token="$(echo_parse_vm_pooler_token "${json_output}")"
  if [[ $? != 0 ]]; then
    echo "unable to parse token output" >&2
    return 1
  fi

  echo "${token}"

  write_vmpooler_token_to_file "${token}"
  if [[ $? != 0 ]]; then
    echo "unable to write new token value to disk" >&2
    return 1
  fi

  return 0
}

### Still in progress; these functions probably need more rigor/abstraction.
###   Metaprogramming in Bash is still considered gauche, right?

vmpooler_platforms() {
  curl \
    --insecure \
    --silent \
    --header "X-AUTH-TOKEN:${VMPOOLER_TOKEN}" \
    --url "${VMPOOLER_URL}/vm/" |
    jq --exit-status --raw-output ".[]"
  return $?
}

vmpooler_status() {
  local host="${1:-UNDEFINED}"

  if [[ ${host} == UNDEFINED ]]; then
    echo "please provide the name of a VM Pooler host to query" >&2
  fi

  curl \
    --insecure \
    --silent \
    --header "X-AUTH-TOKEN:${VMPOOLER_TOKEN}" \
    --url "${VMPOOLER_URL}/vm/${host}" |
    jq --exit-status --raw-output ".\"${host}\".state | select(. == null | not)"
  return $?
}

vmpooler_lifespan() {
  local host="${1:-UNDEFINED}"
  local lifespan="${2:-UNDEFINED}"

  if [[ ${host} == UNDEFINED ]]; then
    echo "please provide the name of a VM Pooler host to delete" >&2
    return 1
  fi

  if [[ ${lifespan} == UNDEFINED ]]; then
    echo "please provide the number of hours to reserve '${host}'" >&2
    return 1
  fi

  if ! test_vmpooler_token; then
    echo "cannot find VM Pooler token, cannot check out pooler VM"
    return 1
  fi

  curl \
    --insecure \
    --request PUT \
    --header "X-AUTH-TOKEN:${VMPOOLER_TOKEN}" \
    --data "{\"lifetime\":\"${lifespan}\"}" \
    --url "${VMPOOLER_URL}/vm/${host}"
  return $?
}

vmpooler_ssh() {
  VMPOOLER_SSH_OPTIONS="-o StrictHostKeyChecking=no ${VMPOOLER_SSH_OPTIONS}"
  VMPOOLER_SSH_OPTIONS="-o UserKnownHostsFile=/dev/null ${VMPOOLER_SSH_OPTIONS}"

  if [[ -n "${VMPOOLER_SSH_KEY}" ]]; then
    VMPOOLER_SSH_OPTIONS="${VMPOOLER_SSH_OPTIONS} -i ${VMPOOLER_SSH_KEY}"
  fi

  IFS=' ' read -r -a __options <<< "${VMPOOLER_SSH_OPTIONS}"
  # shellcheck disable=SC2029
  ssh "${__options[@]}" "${@}"
}

vmpooler_scp() {
  VMPOOLER_SSH_OPTIONS="-o StrictHostKeyChecking=no ${VMPOOLER_SSH_OPTIONS}"
  VMPOOLER_SSH_OPTIONS="-o UserKnownHostsFile=/dev/null ${VMPOOLER_SSH_OPTIONS}"

  if [[ -n "${VMPOOLER_SSH_KEY}" ]]; then
    VMPOOLER_SSH_OPTIONS="${VMPOOLER_SSH_OPTIONS} -i ${VMPOOLER_SSH_KEY}"
  fi

  IFS=' ' read -r -a __options <<< "${VMPOOLER_SSH_OPTIONS}"
  scp "${__options[@]}" "${@}"
}

### User interface!
###   We has it!

help_screen() {
  echo "Please use one of the following commands:"
  echo
  echo "List Pooler Platforms:"
  echo "  platforms"
  echo
  echo "Pooler VM Management:"
  echo "  checkout <platform tag>"
  echo "  destroy <lease name>"
  echo "  lifespan <lease name> <duration>"
  echo "  status <lease name>"
  echo "  leases"
  echo
  echo "Pooler VM Connectivity:"
  echo "  ssh <lease name>"
  echo "  scp <file(s)> <lease name>:<path>"
  echo
  echo "Pooler Auth Token Management:"
  echo "  authorize <ldap username>"
  echo "  deauthorize <token>"
  echo "  tokens <ldap username>"
  echo
  echo "Client Configuration:"
  echo "  config"
  echo
  echo "Developmental metadata:"
  echo "  todo"

  return 0
}

todo() {
  local todos=(
    "VM tagging"
    "list all assigned tokens"
    "allow token deletion"
    "improve VM lifespan management"
    "display VM status (active, destroyed) in leases"
    "normalize & refactor curl commands out of functions"
    "normalize & refactor API endpoints out of functions"
    "dependency checking for basename and jq"
    "improve the README"
    "write a man page?"
    "bash completion"
    "color output?"
    "create config file"
    "edit config file values"
    "command line flags for subcommands"
    "refactor output handling; less raw 'echo' calls"
  )

  for todo in "${todos[@]}"; do
    echo "- ${todo}"
  done
  return 0
}

vmpooler() {
  local action="${1:-UNDEFINED}"
  shift

  parse_config

  case "${action}" in
    platforms)
      vmpooler_platforms
    ;;
    checkout)
      vmpooler_checkout "$(echo_downcase "${1}")"
    ;;
    destroy)
      vmpooler_destroy "$(echo_downcase "${1}")"
    ;;
    status)
      vmpooler_status "$(echo_downcase "${1}")"
    ;;
    lifespan)
      vmpooler_lifespan "${@}"
    ;;
    leases)
      vmpooler_leases
    ;;
    authorize)
      vmpooler_authorize "${1}"
    ;;
    ssh)
      vmpooler_ssh "${@}"
    ;;
    scp)
      vmpooler_scp "${@}"
    ;;
    config)
      print_config
    ;;
    todo)
      todo
    ;;
    commands)
      echo "platforms checkout destroy status lifespan leases authorize ssh scp help"
    ;;
    *)
      help_screen
    ;;
  esac
  return $?
}

vmpooler "${@}"
