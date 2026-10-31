ARG RUBY_VERSION=3.4.12
FROM ruby:${RUBY_VERSION}-bookworm
RUN gem install --no-document json:2.19.9 jwt:3.3.0 base64:0.3.0 openssl:4.0.2 digest:3.2.1 && \
    curl --fail --silent --show-error --proto '=https' --max-time 60 https://rubygems.org/downloads/ap2_mandate_verifier-0.5.0.gem -o /tmp/published.gem && \
    test "$(wc -c < /tmp/published.gem)" -eq 50688 && \
    echo '00b0ce0981070864c67a056906c5af204bbc5aaa80d029cb4a64294634367dd8  /tmp/published.gem' | sha256sum -c - && \
    gem install --local --no-document /tmp/published.gem && rm /tmp/published.gem
WORKDIR /src
