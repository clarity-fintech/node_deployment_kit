#!/usr/bin/env bash
# Delegates to cf_tunnel_bootstrap.sh (clarity-fintech.com, not clrty.dev)
exec "$(cd "$(dirname "$0")" && pwd)/cf_tunnel_bootstrap.sh" "$@"
