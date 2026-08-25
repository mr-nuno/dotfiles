#!/bin/sh
# Copy into a project as `docker-entrypoint.sh`.
# Derives runtime env vars before nginx starts, then hands off to nginx's official
# entrypoint so it substitutes ${VARS} in /etc/nginx/templates/*.template.
set -e

# Example (per house Docker rules): derive a value before startup, e.g. base64-decode
# a secret into an env var referenced by nginx.conf.template. Uncomment + adapt:
# if [ -n "$AUTH_B64" ]; then
#     export BASIC_AUTH="$(printf '%s' "$AUTH_B64" | base64 -d)"
# fi

# nginx's official entrypoint runs the /etc/nginx/templates/ env substitution, then CMD.
exec /docker-entrypoint.sh nginx -g 'daemon off;'
