ARG RUBY_VERSION=4.0.9
FROM ruby:${RUBY_VERSION}-bookworm
RUN gem install --no-document json:2.19.9 jwt:3.3.0 base64:0.3.0 openssl:4.0.2 digest:3.2.1 bundler:4.0.20 && \
    mkdir -p /opt/ap2 && \
    curl --fail --silent --show-error --proto '=https' --max-time 60 https://rubygems.org/downloads/ap2_mandate_verifier-1.6.0.gem -o /opt/ap2/published.gem && \
    test "$(wc -c < /opt/ap2/published.gem)" -eq 186368 && \
    echo '62de85123e1379c538c9c4302b71a9c55c590162591169a4e335aaa03a8991f8  /opt/ap2/published.gem' | sha256sum -c - && \
    gem install --local --no-document /opt/ap2/published.gem
# Core SDK must load with no Rails/SQLite driver installed or activated.
RUN ruby -e 'require "ap2_mandate_verifier"; abort if defined?(Rails) || defined?(SQLite3); abort unless Gem::Specification.find_all_by_name("sqlite3").empty?; puts "PASS published core without Rails or SQLite"'
# Optional reference persistence driver for tests/examples, not a Gem runtime dependency.
RUN set -eu; \
    case "$(uname -m)" in \
      aarch64) platform=aarch64-linux-gnu; expected=e9aea2c2b3476fc875dd8a89313a9a2862818519c0186bfb5b56d6f57bb08d98 ;; \
      x86_64) platform=x86_64-linux-gnu; expected=ca92731ab464df9cae503fa1a439a549e2724f6953c8c05a7769b59366e38f15 ;; \
      *) exit 1 ;; \
    esac; \
    curl --fail --silent --show-error --proto '=https' --max-time 60 "https://rubygems.org/downloads/sqlite3-2.10.2-${platform}.gem" -o /tmp/sqlite3.gem; \
    printf '%s  %s\n' "$expected" /tmp/sqlite3.gem | sha256sum -c -; \
    gem install --local --no-document /tmp/sqlite3.gem; \
    rm /tmp/sqlite3.gem; \
    ruby -e 'gem "sqlite3", "= 2.10.2"; require "sqlite3"; abort unless SQLite3::VERSION == "2.10.2"'
WORKDIR /src
WORKDIR /app
COPY examples/ruby_integration.rb examples/ruby_integration.rb
COPY examples/integration/*.rb examples/integration/
ENTRYPOINT ["ruby", "examples/ruby_integration.rb"]
