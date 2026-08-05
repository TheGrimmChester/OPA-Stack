# Family-root dashboard build for ORA/OSA/OPL/OPM (file: deps on Open-UI-JS / Open-Client-JS).
#   docker build -f OPA-Stack/harness/docker/dashboard.nas.Dockerfile \
#     --build-arg PRODUCT=ORA-Dashboard -t ora-dashboard:nas .
FROM node:18-alpine AS builder
ARG PRODUCT=ORA-Dashboard
# Peer dashboard ports baked into SPA external links (NAS OAM is :18097).
ARG VITE_OAM_DASHBOARD_PORT=8097
ARG VITE_OPM_DASHBOARD_PORT=8098
WORKDIR /family
COPY Open-Client-JS /family/Open-Client-JS
COPY Open-UI-JS /family/Open-UI-JS
COPY ${PRODUCT} /family/${PRODUCT}
WORKDIR /family/Open-Client-JS
RUN npm install && npm run build
WORKDIR /family/Open-UI-JS
RUN npm install && npm run build
WORKDIR /family/${PRODUCT}
ENV VITE_OAM_DASHBOARD_PORT=$VITE_OAM_DASHBOARD_PORT
ENV VITE_OPM_DASHBOARD_PORT=$VITE_OPM_DASHBOARD_PORT
RUN npm install \
 && npm run build

FROM nginx:alpine
ARG PRODUCT=ORA-Dashboard
COPY --from=builder /family/${PRODUCT}/dist /usr/share/nginx/html
COPY --from=builder /family/${PRODUCT}/nginx.conf /etc/nginx/conf.d/default.conf
RUN rm -f /docker-entrypoint.d/10-listen-on-ipv6-by-default.sh
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
