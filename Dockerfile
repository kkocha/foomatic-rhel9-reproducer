FROM registry.access.redhat.com/ubi9/ubi:9.8

RUN dnf -y install \
        cups-filters \
        file \
        findutils \
        gzip \
        less \
        tar \
    && dnf clean all \
    && rm -rf /var/cache/dnf

COPY prepare-ricoh.sh /usr/local/sbin/prepare-ricoh
RUN chmod 0755 /usr/local/sbin/prepare-ricoh \
    && /usr/local/sbin/prepare-ricoh

WORKDIR /workspaces/cups-filters

CMD ["/bin/bash"]
