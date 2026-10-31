ARG RUBY_VERSION=3.4.12
FROM ruby:${RUBY_VERSION}-bookworm
RUN gem install --no-document json:2.19.9 jwt:3.3.0 base64:0.3.0 openssl:4.0.2 digest:3.2.1 bundler:4.0.20
WORKDIR /src
