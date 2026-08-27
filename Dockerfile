FROM elixir:1.20.3-otp-29-slim AS build

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install --yes --no-install-recommends build-essential ca-certificates git && \
    rm -rf /var/lib/apt/lists/*

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

FROM debian:trixie-slim

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install --yes --no-install-recommends ca-certificates curl libncurses6 libsctp1 libstdc++6 openssl && \
    rm -rf /var/lib/apt/lists/* && \
    groupadd --system --gid 1001 memovee && \
    useradd --system --uid 1001 --gid memovee --home-dir /app --create-home memovee

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

CMD ["bin/docker-entrypoint"]
