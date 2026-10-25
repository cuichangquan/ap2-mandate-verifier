# Source-only; no syntax/run approval is supplied with this preparation.
# Own only the child groups created here; no unrelated processes or credentials.
require 'rbconfig'
ROOT = '/results'
def tick(pid)
  File.read("/proc/#{pid}/stat").rpartition(') ').last.split.fetch(19)
rescue Errno::ENOENT
  nil
end
def record(path, text)
  File.open(path, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |f| f.write(text) }
end
def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
def bounded_reap(pid)
  limit = now + 2
  loop do
    return if Process.waitpid(pid, Process::WNOHANG)
    raise 'leader wait UNKNOWN' if now >= limit
    sleep 0.05
  end
end
if ARGV == ['--settle-owned']
  raw = File.read("#{ROOT}/install.supervisor")
  pid, start = raw.split
  raise 'invalid owned supervisor receipt' unless pid.match?(/\A[1-9][0-9]*\z/) && start.match?(/\A[0-9]+\z/)
  pid = Integer(pid)
  if tick(pid) == start
    cmd = File.binread("/proc/#{pid}/cmdline").split("\0")
    raise 'owned command mismatch' unless cmd.include?('/supervision/offline_install.rb')
    Process.kill('TERM', pid)
    deadline = now + 10
    sleep 0.05 while tick(pid) == start && now < deadline
    raise 'owned installer still present' if tick(pid) == start
  end
  raw = File.read("#{ROOT}/install.finished")
  raise 'group recovery UNKNOWN' unless raw.match?(/\A[0-9]+ recovered\n\z/)
  puts raw
  exit
end
raise 'unexpected arguments' unless ARGV.empty?
record("#{ROOT}/install.supervisor", "#{Process.pid} #{tick(Process.pid)}\n")
child = nil
reaped = false
recovered = true
exit_code = 1
trap('TERM') { raise Interrupt, 'owned installer TERM' }
trap('INT') { raise Interrupt, 'owned installer INT' }
begin
  jobs = [
    ['json', 180, ['/archives/json-2.19.9.gem']],
    ['other', 30, ['/archives/jwt-3.3.0.gem', '/archives/base64-0.3.0.gem', '/archives/pg-1.7.0-aarch64-linux.gem']]
  ]
  jobs.each do |name, seconds, archives|
    child = Process.spawn(RbConfig.ruby, '-S', 'gem', 'install', '--local', '--no-document',
                          '--ignore-dependencies', *archives, pgroup: true)
    reaped = false
    record("#{ROOT}/install.#{name}.group", "#{child} #{child} #{tick(child)}\n")
    limit = now + seconds
    status = nil
    until status
      waited = Process.waitpid2(child, Process::WNOHANG)
      if waited
        status = waited[1]
        reaped = true
        break
      end
      raise "#{name} timeout" if now >= limit
      sleep 0.05
    end
    record("#{ROOT}/install.#{name}.exit", "#{status.exitstatus || 128 + status.termsig}\n")
    raise "#{name} install failed" unless status.success?
    # Even a successful leader must leave no background descendants in its group.
    begin
      Process.kill(0, -child)
      raise 'installer background group still present'
    rescue Errno::ESRCH
      child = nil
    end
  end
  exit_code = 0
rescue Exception => error
  warn "#{error.class}: #{error.message}"
  exit_code = error.is_a?(Interrupt) ? 130 : 1
ensure
  if child
    begin
      Process.kill('TERM', -child)
      limit = now + 2
      loop do
        unless reaped
          waited = Process.waitpid2(child, Process::WNOHANG)
          reaped = true if waited
        end
        begin
          Process.kill(0, -child)
        rescue Errno::ESRCH
          break
        end
        break if now >= limit
        sleep 0.05
      end
      begin
        Process.kill('KILL', -child)
      rescue Errno::ESRCH
      end
      bounded_reap(child) unless reaped
      limit = now + 2
      loop do
        begin
          Process.kill(0, -child)
        rescue Errno::ESRCH
          break
        end
        raise 'descendant group recovery UNKNOWN' if now >= limit
        sleep 0.05
      end
    rescue Errno::ESRCH
      begin
        bounded_reap(child) unless reaped
      rescue Exception => error
        recovered = false
        warn "recovery #{error.class}: #{error.message}"
      end
    rescue Exception => error
      recovered = false
      warn "recovery #{error.class}: #{error.message}"
    end
  end
  record("#{ROOT}/install.finished", "#{exit_code} #{recovered ? 'recovered' : 'UNKNOWN'}\n")
end
exit(recovered ? exit_code : 2)
