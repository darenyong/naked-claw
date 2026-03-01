# Stage 1: Build
FROM debian:bookworm-slim AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    sbcl curl ca-certificates libssl-dev make gcc libc6-dev \
    && rm -rf /var/lib/apt/lists/*

# Install Quicklisp
RUN curl -o /tmp/quicklisp.lisp https://beta.quicklisp.org/quicklisp.lisp \
    && sbcl --non-interactive --load /tmp/quicklisp.lisp \
       --eval '(quicklisp-quickstart:install)' \
       --eval '(quit)'

WORKDIR /build
COPY naked-claw.asd build.lisp package.lisp primitives.lisp \
     config.lisp buffer.lisp compact.lisp llm.lisp telegram.lisp main.lisp ./

RUN sbcl --non-interactive --load build.lisp

# Stage 2: Runtime
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates libssl3 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /build/naked-claw /usr/local/bin/naked-claw

CMD ["naked-claw"]
