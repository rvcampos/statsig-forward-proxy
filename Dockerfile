FROM rust:1.83-alpine3.19 AS builder
RUN apk update 
RUN apk add git curl build-base autoconf automake libtool pkgconfig libressl-dev musl-dev gcc libc-dev g++ libffi-dev unzip

ARG TARGETPLATFORM
ARG PROTOBUFVER=26.0
RUN case ${TARGETPLATFORM} in \
         "linux/amd64")  PBF_ARCH=x86_64   ;; \
         "linux/arm64"|"linux/arm64/v8")  PBF_ARCH=aarch_64 ;; \
         "linux/386")    PBF_ARCH=x86_32   ;; \
    esac \
&& curl -LO https://github.com/protocolbuffers/protobuf/releases/download/v${PROTOBUFVER}/protoc-${PROTOBUFVER}-linux-${PBF_ARCH}.zip \ 
&& unzip protoc-${PROTOBUFVER}-linux-${PBF_ARCH}.zip

RUN cp ./bin/protoc /usr/bin/protoc

# create a new empty shell project, copy dependencies
# and install to allow caching of dependencies
RUN USER=root cargo new --bin statsig_forward_proxy
WORKDIR /statsig_forward_proxy
COPY ./Cargo.lock ./Cargo.lock
COPY ./Cargo.toml ./Cargo.toml
COPY ./rust-toolchain.toml ./rust-toolchain.toml
RUN cp ./src/main.rs ./src/server.rs
RUN cp ./src/main.rs ./src/client.rs
RUN rustup update
RUN cargo build --release
RUN rm src/*.rs

# Copy Important stuff and then build final binary
COPY ./src ./src
COPY ./build.rs ./build.rs
COPY ./api-interface-definitions ./api-interface-definitions
RUN rm ./target/release/deps/server*
RUN cargo build --release

FROM nginx:alpine

# Copy the build artifact from the build stage
COPY --from=builder /statsig_forward_proxy/target/release/server /usr/local/bin/statsig_forward_proxy

# Copy other necessary files
COPY ./.cargo /app/.cargo
COPY ./Rocket.toml /app/Rocket.toml

# Set working directory
WORKDIR /app

# Set environment variable
ENV ROCKET_ENV=prod

# Expose port 8001 for Nginx and 8000 for the proxy
EXPOSE 8000 8001

# Copy Nginx configuration
COPY nginx.conf.template /nginx.conf.template
# Create an entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Use ENTRYPOINT to run the script
ENTRYPOINT ["/entrypoint.sh"]
