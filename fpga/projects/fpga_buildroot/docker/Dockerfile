FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8
ENV WORKSPACE=/workspace
ENV CMAKE_TOOLCHAIN_FILE=/workspace/tools/toolchain-arm-linux-gnueabihf-kuiper.cmake
ENV CMAKE_EXPORT_COMPILE_COMMANDS=1

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    cmake \
    file \
    g++ \
    gcc \
    gcc-arm-linux-gnueabihf \
    g++-arm-linux-gnueabihf \
    binutils-arm-linux-gnueabihf \
    libc6-dev-armhf-cross \
    linux-libc-dev-armhf-cross \
    make \
    pkg-config \
    git \
    rsync \
    gdb \
    gdb-multiarch \
    openssh-server \
    sudo \
    less \
    nano \
    vim-tiny \
    python3 \
 && rm -rf /var/lib/apt/lists/*

RUN useradd -m -s /bin/bash -u 1000 dev \
 && echo 'dev:dev' | chpasswd \
 && adduser dev sudo \
 && echo 'dev ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/90-dev \
 && chmod 0440 /etc/sudoers.d/90-dev

RUN mkdir -p /run/sshd /workspace /home/dev/.ssh \
 && chown -R dev:dev /workspace /home/dev/.ssh \
 && chmod 700 /home/dev/.ssh

COPY docker/prepare-kuiper-sysroot.sh /usr/local/bin/prepare-kuiper-sysroot
RUN chmod +x /usr/local/bin/prepare-kuiper-sysroot

RUN sed -ri 's/^#?PasswordAuthentication\s+.*/PasswordAuthentication yes/' /etc/ssh/sshd_config \
 && sed -ri 's/^#?PermitRootLogin\s+.*/PermitRootLogin no/' /etc/ssh/sshd_config \
 && sed -ri 's/^#?UsePAM\s+.*/UsePAM yes/' /etc/ssh/sshd_config \
 && printf '\nAllowUsers dev\n' >> /etc/ssh/sshd_config

EXPOSE 22

WORKDIR /workspace

CMD ["/usr/sbin/sshd", "-D", "-e"]
