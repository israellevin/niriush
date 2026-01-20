# Dockerfile to build niri.
FROM debian:sid

# Install dependencies.
RUN apt update
RUN apt install -y \
    build-essential \
    clang \
    curl \
    gcc \
    git \
    libdbus-1-dev \
    libdisplay-info-dev \
    libegl1-mesa-dev \
    libgbm-dev \
    libinput-dev \
    libpango1.0-dev \
    libpipewire-0.3-dev \
    libseat-dev \
    libsystemd-dev \
    libudev-dev \
    libwayland-dev \
    libxcb-cursor-dev \
    libxkbcommon-dev

# Install Rust and cargo-strip.
RUN curl https://sh.rustup.rs -sSf | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"
RUN cargo install --force cargo-strip

# Build xwayland-satellite, for X, you know.
WORKDIR /
RUN git clone https://github.com/Supreeeme/xwayland-satellite
WORKDIR /xwayland-satellite
RUN cargo build --release
RUN cargo strip

# Use `docker build --build-arg NEW_NIRI=$(date +%s)` to force rebuild from here.
ARG NEW_NIRI
WORKDIR /
RUN git clone https://github.com/YaLTeR/niri
WORKDIR /niri
RUN cargo build --release
RUN cargo strip

# Prepare the package directory.
RUN mkdir -p /package/usr/local/bin
RUN cp -a /niri/target/release/niri /package/usr/local/bin/.
RUN cp -a /xwayland-satellite/target/release/xwayland-satellite /package/usr/local/bin/.

# Serve the package directory all tarred up.
RUN apt install -y netcat-openbsd
CMD sh -c '( \
    printf "HTTP/1.0 200 OK\r\nContent-Type: application/x-tar\r\n\r\n"; \
    tar -C /package -cf - . \; \
    echo \
) | nc -lp80 -q0'
