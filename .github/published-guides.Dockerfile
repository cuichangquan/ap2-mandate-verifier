ARG RUBY_VERSION=3.4.12
FROM ruby:${RUBY_VERSION}-bookworm
RUN gem install --no-document json:2.19.9 jwt:3.3.0 base64:0.3.0 openssl:4.0.2 digest:3.2.1 && \
    curl --fail --silent --show-error --proto '=https' --max-time 60 https://rubygems.org/downloads/ap2_mandate_verifier-1.4.0.gem -o /tmp/published.gem && \
    test "$(wc -c < /tmp/published.gem)" -eq 145920 && \
    echo 'ea82c6468f339ed280005e1a270a511b1a8594452ef3de6fb546de43aa6ba454  /tmp/published.gem' | sha256sum -c - && \
    gem install --local --no-document /tmp/published.gem && rm /tmp/published.gem
WORKDIR /src
