# Family-root dashboard build for ORA/OSA/OPL/OPM/OAM/OPA (file: deps on Open-UI-JS / Open-Client-JS).
#   docker build -f OPA-Stack/harness/docker/dashboard.nas.Dockerfile \
#     --build-arg PRODUCT=ORA-Dashboard \
#     --build-arg VITE_OAM_URL=http://192.168.100.101:18097 \
#     -t ora-dashboard:nas .
FROM node:18-alpine AS builder
ARG PRODUCT=ORA-Dashboard
# Absolute OAM dashboard origin for login + “Manage in Account Manager” deep-links.
ARG VITE_OAM_URL=
ENV VITE_OAM_URL=$VITE_OAM_URL
WORKDIR /family
COPY Open-Client-JS /family/Open-Client-JS
COPY Open-UI-JS /family/Open-UI-JS
COPY ${PRODUCT} /family/${PRODUCT}
WORKDIR /family/Open-Client-JS
RUN npm install && npm run build
WORKDIR /family/Open-UI-JS
RUN npm install && npm run build
WORKDIR /family/${PRODUCT}
RUN npm install \
 && npm run build

FROM nginx:alpine
ARG PRODUCT=ORA-Dashboard
COPY --from=builder /family/${PRODUCT}/dist /usr/share/nginx/html
COPY --from=builder /family/${PRODUCT}/nginx.conf /etc/nginx/conf.d/default.conf
RUN rm -f /docker-entrypoint.d/10-listen-on-ipv6-by-default.sh
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
