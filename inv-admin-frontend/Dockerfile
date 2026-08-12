FROM node:24-alpine AS builder

WORKDIR /app

COPY package*.json ./

RUN npm ci --registry=https://registry.npmmirror.com

COPY . .

# 外部服务地址（CDN 多子域模式），构建时通过 --build-arg 注入；
# 不注入则回退到同源相对路径（单域部署 / 本地开发）。
ARG VITE_API_BASE=""
ARG VITE_WS_BASE=""
ENV VITE_API_BASE=$VITE_API_BASE
ENV VITE_WS_BASE=$VITE_WS_BASE

RUN npm run build

FROM alpine:3.23

ARG ALPINE_MIRROR=dl-cdn.alpinelinux.org
RUN sed -i "s/dl-cdn.alpinelinux.org/${ALPINE_MIRROR}/g" /etc/apk/repositories && \
    apk add --no-cache nginx && \
    mkdir -p /run/nginx /var/lib/nginx/logs /var/log/nginx && \
    chown -R 101:101 /run/nginx /var/lib/nginx /var/log/nginx

COPY --from=builder /app/dist /usr/share/nginx/html

COPY nginx.conf /etc/nginx/http.d/default.conf

USER 101

EXPOSE 8080

CMD ["nginx", "-g", "daemon off;"]
