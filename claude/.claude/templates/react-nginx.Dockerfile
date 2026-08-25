# Dockerfile — React SPA built once, served by nginx; runtime config via env vars.
# See .claude/rules/code-docker.md. Ships with react-nginx.nginx.conf.template and
# react-nginx.entrypoint.sh (copy them beside this file, renamed as noted below).
#
# Build context = the frontend app dir.
#   docker build -t myspa .
#   docker run -e API_URL=https://api.example.com -p 8080:80 myspa

FROM node:24-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build              # outputs to /app/dist

FROM nginx:alpine AS final
COPY --from=build /app/dist /usr/share/nginx/html

# nginx auto-substitutes ${VARS} in /etc/nginx/templates/*.template at container start.
# (copy react-nginx.nginx.conf.template -> nginx.conf.template)
COPY nginx.conf.template /etc/nginx/templates/default.conf.template
# Custom entrypoint derives env vars first, then chains to nginx's template processing.
# (copy react-nginx.entrypoint.sh -> docker-entrypoint.sh)
COPY docker-entrypoint.sh /docker-entrypoint-custom.sh
RUN chmod +x /docker-entrypoint-custom.sh

# Runtime configuration — override per environment (docker run -e / compose).
ENV API_URL=http://api:8080

EXPOSE 80
ENTRYPOINT ["/docker-entrypoint-custom.sh"]
