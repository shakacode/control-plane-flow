FROM busybox:1.37.0

ARG GIT_COMMIT
RUN mkdir /www && printf '%s\n' "$GIT_COMMIT" > /www/index.html

EXPOSE 3000
CMD ["httpd", "-f", "-p", "3000", "-h", "/www"]
