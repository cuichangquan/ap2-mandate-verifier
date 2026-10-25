# Source-only preparation. Do not execute without a new bounded approval.
require 'digest'
STDOUT.sync = true
count = 0
total = 0
visited = 0
patterns = %w[mkmf.log gem_make.out extconf.h Makefile conftest*]
%w[/opt/hcr-gems /tmp].each do |root|
  # No environment, credentials, DB files, or arbitrary home files are collected.
  stack = [root]
  until stack.empty?
    dir = stack.pop
    visited += 1
    raise 'directory traversal cap' if visited > 4096
    Dir.children(dir).sort.each do |name|
      path = File.join(dir, name)
      st = File.lstat(path)
      raise 'symlink in diagnostic traversal' if st.symlink?
      if st.directory?
        stack << path
        raise 'directory traversal cap' if stack.size > 2048
        next
      end
      next unless patterns.any? { |pattern| File.fnmatch?(pattern, name) }
      raise 'nonregular diagnostic' unless st.file?
      raise 'diagnostic path characters' if path.match?(/[\x00-\x1f\x7f]/)
      count += 1
      total += st.size
      raise 'diagnostic cap' if count > 256 || st.size > 2*1024*1024 || total > 8*1024*1024
      File.open(path, File::RDONLY | File::NOFOLLOW) do |f|
        raise 'diagnostic replaced' unless f.stat.ino == st.ino && f.stat.dev == st.dev
        data = f.read(2*1024*1024+1)
        raise 'diagnostic changed' unless data.bytesize == st.size && f.stat.size == st.size && f.stat.mtime == st.mtime
        puts ['FILE', Digest::SHA256.hexdigest(data), data.bytesize, path, [data].pack('m0')].join("\t")
      end
    end
  end
end
puts 'COMPLETE'
