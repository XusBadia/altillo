#!/bin/zsh
# Throwaway Home Assistant (demo integration) for developing and recording Altillo's Home section
# without touching a real home.
#
#   script/home-lab.sh up      # start, onboard, print URL and save a long-lived token
#   script/home-lab.sh token   # print the saved token
#   script/home-lab.sh down    # stop and remove the container (config and token stay)
#   script/home-lab.sh reset   # down + wipe config and token
#
# Runs on http://localhost:8124 so it never clashes with a real Home Assistant on 8123.
set -euo pipefail

name=altillo-home-lab
image=ghcr.io/home-assistant/home-assistant:stable
port=8124
url=http://localhost:$port
dir=$HOME/Library/Caches/altillo-home-lab
token_file=$dir/token
helper=${0:A:h}/home-lab/mint_token.py
user=altillo password=altillo-lab-pass client=http://localhost:$port/

die() { print -u2 "home-lab: $*"; exit 1; }

ensure_docker() {
  command -v docker >/dev/null || die "docker not found (install Docker Desktop)"
  if ! docker info >/dev/null 2>&1; then
    print "Starting Docker Desktop..."
    open -a Docker
    for _ in {1..90}; do docker info >/dev/null 2>&1 && return; sleep 2; done
    die "Docker daemon did not come up"
  fi
}

json() { python3 -c "import sys,json; print(json.load(sys.stdin)[sys.argv[1]])" "$1"; }

up() {
  ensure_docker
  mkdir -p $dir
  [[ -f $dir/configuration.yaml ]] || print 'default_config:\ndemo:' > $dir/configuration.yaml
  if [[ -z $(docker ps -q -f name=^$name\$) ]]; then
    docker rm -f $name >/dev/null 2>&1 || true
    docker run -d --name $name --restart unless-stopped -p 127.0.0.1:$port:8123 \
      -v $dir:/config -e TZ=${TZ:-Europe/Madrid} $image >/dev/null
  fi
  print -n "Waiting for Home Assistant"
  for _ in {1..120}; do
    curl -fs -o /dev/null $url/api/onboarding && break
    print -n .; sleep 2
  done
  curl -fs -o /dev/null $url/api/onboarding || die "Home Assistant did not answer on $url"
  print

  if [[ ! -s $token_file ]]; then
    local pending
    pending=$(curl -fs $url/api/onboarding | python3 -c "import sys,json; print(any(not s['done'] and s['step']=='user' for s in json.load(sys.stdin)))")
    [[ $pending == True ]] || die "already onboarded but no saved token; run: script/home-lab.sh reset && script/home-lab.sh up"
    local code access
    code=$(curl -fs -X POST $url/api/onboarding/users -H 'Content-Type: application/json' \
      -d "{\"client_id\":\"$client\",\"name\":\"Altillo Lab\",\"username\":\"$user\",\"password\":\"$password\",\"language\":\"en\"}" | json auth_code)
    access=$(curl -fs -X POST $url/auth/token -d grant_type=authorization_code -d "code=$code" -d "client_id=$client" | json access_token)
    for step in core_config analytics; do
      curl -fs -X POST $url/api/onboarding/$step -H "Authorization: Bearer $access" -H 'Content-Type: application/json' -d '{}' >/dev/null || true
    done
    curl -fs -X POST $url/api/onboarding/integration -H "Authorization: Bearer $access" -H 'Content-Type: application/json' \
      -d "{\"client_id\":\"$client\",\"redirect_uri\":\"$client\"}" >/dev/null || true
    HA_ACCESS_TOKEN=$access docker exec -i -e HA_ACCESS_TOKEN $name python3 - < $helper > $token_file.tmp
    [[ -s $token_file.tmp ]] || die "could not mint a long-lived token"
    mv $token_file.tmp $token_file; chmod 600 $token_file
  fi

  local n
  for _ in {1..30}; do
    n=$(curl -fs $url/api/states -H "Authorization: Bearer $(<$token_file)" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo 0)
    (( n > 5 )) && break; sleep 2
  done
  print "Home Assistant lab ready: $url  ($n entities)"
  print "Login: $user / $password"
  print "Token saved in: $token_file  (script/home-lab.sh token)"
}

case ${1:-} in
  up) up ;;
  token) [[ -s $token_file ]] || die "no token yet; run: script/home-lab.sh up"; cat $token_file ;;
  down) ensure_docker; docker rm -f $name >/dev/null 2>&1 || true; print "Removed $name" ;;
  reset) ensure_docker; docker rm -f $name >/dev/null 2>&1 || true; rm -rf $dir; print "Removed $name and $dir" ;;
  *) print -u2 "usage: script/home-lab.sh up|token|down|reset"; exit 2 ;;
esac
