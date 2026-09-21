FROM nginxinc/nginx-unprivileged:alpine
COPY ./dist /usr/share/nginx/html
EXPOSE 8080