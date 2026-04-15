# set-environment references variables (e.g. XDG_STATE_HOME) that don't exist
# in the clearenv'd sandbox, so temporarily allow unbound references.
set +u
# shellcheck source=/dev/null
source /etc/set-environment
set -u

if [[ ${1:-} == "--direnv" ]]; then
  shift
  direnv allow .
  # shellcheck source=/dev/null
  source <(direnv export bash)
fi

exec "$@"
