ARG RUBY_VERSION=3.4.12
FROM ruby:${RUBY_VERSION}-bookworm
RUN gem install --no-document json:2.19.9 jwt:3.3.0 base64:0.3.0 openssl:4.0.2 digest:3.2.1 && \
    curl --fail --silent --show-error --proto '=https' --max-time 60 https://rubygems.org/downloads/ap2_mandate_verifier-1.3.0.gem -o /tmp/published.gem && \
    test "$(wc -c < /tmp/published.gem)" -eq 137728 && \
    echo 'fb95cf669bc4cba1cc1360653bfd7ae8aec58404f13810f6d5a8fb205bc8841d  /tmp/published.gem' | sha256sum -c - && \
    gem install --local --no-document /tmp/published.gem && rm /tmp/published.gem
WORKDIR /src
