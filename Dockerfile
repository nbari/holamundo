FROM nginx:latest 
VOLUME ./filesnginx
COPY ./index.html /usr/share/nginx/html/index.html