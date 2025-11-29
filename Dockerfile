# Use a recent Alpine for compatibility
FROM filebrowser/filebrowser:v2-s6
# Install build dependencies and build Fossil from trunk
RUN apk update && \
    apk upgrade

RUN apk add git openssh && \
    apk add --no-cache curl gcc make tcl musl-dev openssl-dev zlib-dev openssl-libs-static zlib-static && \
    curl "https://fossil-scm.org/home/tarball/fossil-src.tar.gz?name=fossil-src&uuid=trunk" -o fossil-src.tar.gz && \
    tar xf fossil-src.tar.gz && \
    cd fossil-src && \
    ./configure --static --disable-fusefs --with-th1-docs --with-th1-hooks && \
    make && \
    cp fossil /usr/local/bin && \
    cd .. && \
    rm -rf fossil-src fossil-src.tar.gz

EXPOSE 8080
EXPOSE 8081
COPY --chmod=755 run.sh ./

ENTRYPOINT ["/bin/sh"]
CMD ["run.sh"]
