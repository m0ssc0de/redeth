# Stage 1: Building the binary
FROM rust as builder
WORKDIR /usr/src
RUN USER=root cargo new generator
WORKDIR /usr/src/generator
COPY ./ ./
RUN cargo build --release

# Stage 2: Copying the binary to a new image
FROM debian:buster-slim
RUN apt-get update && apt-get install -y libssl1.1 ca-certificates && rm -rf /var/lib/apt/lists/*
COPY --from=builder /usr/src/generator/target/release/generator /usr/local/bin/
CMD ["generator"]