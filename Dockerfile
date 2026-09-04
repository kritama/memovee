FROM alpine:3.24 AS development

ARG LOCAL_UID=1000
ARG LOCAL_GID=1000

RUN apk add --no-cache \
    build-base \
    ca-certificates \
    curl \
    elixir \
    erlang-dev \
    git \
    inotify-tools && \
    addgroup -g "${LOCAL_GID}" -S memovee && \
    adduser -S -D -u "${LOCAL_UID}" -G memovee -h /home/memovee memovee && \
    mkdir -p /app/deps /app/_build && \
    chown -R memovee:memovee /app /home/memovee

WORKDIR /app

ENV HOME=/home/memovee
ENV MIX_ENV=dev

USER memovee

RUN mix local.hex --force && \
    mix local.rebar --force

CMD ["mix", "phx.server"]

FROM alpine:3.24 AS build

RUN apk add --no-cache build-base ca-certificates elixir erlang-dev git

WORKDIR /app

ENV MIX_ENV=prod

RUN mix local.hex --force && \
    mix local.rebar --force

COPY mix.exs mix.lock ./
COPY config/config.exs config/prod.exs config/
RUN mix deps.get --only prod && mix deps.compile

COPY assets assets/
COPY priv priv/
COPY lib lib/

RUN mix compile
RUN mix assets.deploy

# Runtime configuration is evaluated when the release starts and does not
# need to be compiled into the application.
COPY config/runtime.exs config/
COPY rel rel/

RUN mix release

FROM alpine:3.24 AS runtime

RUN apk add --no-cache ca-certificates curl libstdc++ ncurses-libs openssl && \
    addgroup -g 1001 -S memovee && \
    adduser -S memovee -u 1001 -G memovee -h /app

WORKDIR /app

COPY --from=build --chown=memovee:memovee /app/_build/prod/rel/memovee ./

USER memovee

EXPOSE 4000

ENV HOME=/app
ENV LANG=C.UTF-8
ENV MIX_ENV=prod
ENV PORT=4000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD curl -f http://localhost:$PORT/ || exit 1

FROM runtime AS server

CMD ["bin/docker-entrypoint"]
