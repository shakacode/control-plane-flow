ARG RUBY_VERSION=__RUBY_VERSION__

# Node and Ruby base images share the same Debian release so that glibc, libssl, and
# other system libraries line up between stages.
FROM docker.io/library/node:22-bookworm-slim AS node
FROM ruby:$RUBY_VERSION-slim-bookworm

# Yarn Classic / pnpm fallbacks for projects that haven't adopted corepack via
# `packageManager` in package.json. Override at build time (`--build-arg=YARN_CLASSIC_VERSION=...`)
# rather than editing this file so regenerating the Dockerfile keeps your pin.
ARG YARN_CLASSIC_VERSION=1.22.22
ARG PNPM_FALLBACK_VERSION=9.12.3

WORKDIR /app

# Keep Node.js available both for asset compilation and for SSR runtimes that
# rely on ExecJS in production. Narrowed to just what the node stage actually
# ships under /usr/local so we don't drag in unused Debian libs from that image.
COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/bin/npm /usr/local/bin/npm
COPY --from=node /usr/local/bin/npx /usr/local/bin/npx
COPY --from=node /usr/local/bin/corepack /usr/local/bin/corepack
COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules
COPY --from=node /usr/local/include/node /usr/local/include/node

# Expose Corepack-managed shims so later build steps can call yarn/pnpm
# directly during asset precompilation hooks.
RUN printf '%s\n' '#!/bin/sh' 'exec corepack yarn "$@"' > /usr/bin/yarn && \
    chmod +x /usr/bin/yarn && \
    printf '%s\n' '#!/bin/sh' 'exec corepack pnpm "$@"' > /usr/bin/pnpm && \
    chmod +x /usr/bin/pnpm

# install ruby gems
COPY Gemfile* ./

RUN bundle config set without 'development test' && \
    bundle config set with 'production' && \
    bundle install --jobs=3 --retry=3

COPY . ./

# Install JavaScript dependencies only when the project actually has them.
# Pin `packageManager` in package.json to take the corepack path and avoid the
# YARN_CLASSIC_VERSION / PNPM_FALLBACK_VERSION fallbacks below; the fallbacks exist for
# projects that haven't adopted corepack and should be reviewed periodically as they go stale.
RUN if [ -f package.json ]; then \
      package_manager="$(node -p "require('./package.json').packageManager || ''")"; \
      if [ -f yarn.lock ]; then \
        if printf '%s' "$package_manager" | grep -q '^yarn@'; then \
          corepack prepare "$package_manager" --activate && \
            (corepack yarn install --immutable || corepack yarn install --frozen-lockfile); \
        else \
          npm install -g "yarn@${YARN_CLASSIC_VERSION}" && \
            (yarn install --immutable || yarn install --frozen-lockfile); \
        fi; \
      elif [ -f pnpm-lock.yaml ]; then \
        if printf '%s' "$package_manager" | grep -q '^pnpm@'; then \
          corepack prepare "$package_manager" --activate && \
            corepack pnpm install --frozen-lockfile; \
        else \
          corepack prepare "pnpm@${PNPM_FALLBACK_VERSION}" --activate && \
            corepack pnpm install --frozen-lockfile; \
        fi; \
      elif [ -f package-lock.json ]; then \
        npm ci; \
      else \
        npm install; \
      fi; \
    fi

ENV RAILS_ENV=production

# compiling assets requires any value for ENV of SECRET_KEY_BASE
ENV SECRET_KEY_BASE=NOT_USED_NON_BLANK

__ASSET_PRECOMPILE_HOOK_RUN__
RUN rails assets:precompile

# add entrypoint
COPY .controlplane/entrypoint.sh ./
RUN chmod +x /app/entrypoint.sh
ENTRYPOINT ["/app/entrypoint.sh"]

CMD ["rails", "s"]
