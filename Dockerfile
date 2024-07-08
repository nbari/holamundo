FROM nginx:latest
VOLUME ./filesnginx
ARG CACHEBUST=1
COPY ./index.html /usr/share/nginx/html/index.html