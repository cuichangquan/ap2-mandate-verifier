FROM ruby@sha256:42c18f0c9807ba1349c0253617d7f08ef98b815463b2f7785d97c4efdfd80f4d
ENV GEM_HOME=/opt/hdb-gems GEM_PATH=/opt/hdb-gems:/usr/local/lib/ruby/gems/4.0.0
COPY archives/ /archives/
RUN printf '%b' '9b9025b7cdddafa38d316eca0b2358488e42d417045c1b90d216a9fefe46b79a  /archives/json-2.19.9.gem\n44cc34fbc341c148233cf66641522b4bce0dfb1ce55e8073f05c56f44f4ee546  /archives/jwt-3.3.0.gem\n27337aeabad6ffae05c265c450490628ef3ebd4b67be58257393227588f5a97b  /archives/base64-0.3.0.gem\n101dd3a261000eb64b03ff41a5890674b735b626dbdce88652969b59fb0b1157  /archives/pg-1.7.0-aarch64-linux.gem\n' | sha256sum -c -
RUN test "$(cat /sys/fs/cgroup/cpu.max)" = "200000 100000" && test "$(cat /sys/fs/cgroup/memory.max)" = "2147483648" && test "$(cat /sys/fs/cgroup/memory.swap.max)" = "0"
RUN timeout 180 gem install --local --no-document --ignore-dependencies /archives/json-2.19.9.gem && gem install --local --no-document --ignore-dependencies /archives/jwt-3.3.0.gem /archives/base64-0.3.0.gem /archives/pg-1.7.0-aarch64-linux.gem
COPY compare.rb worker.rb schema.sql /research/
WORKDIR /research
USER 1000:1000
CMD ["ruby","compare.rb","--execute-approved"]
