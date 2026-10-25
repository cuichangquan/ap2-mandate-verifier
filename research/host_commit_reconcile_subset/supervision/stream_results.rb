# Read only the fixed result inventory. No recursive discovery or environment dump.
require 'digest'
ROOT = '/results'
COMMON = %w[launch.pid install.supervisor install.json.group install.json.exit install.other.group install.other.exit install.finished]
BATCH = %w[BATCH.json WORKER_REPORT.json SUPERVISION.json REPORT.json controller.stdout controller.stderr worker.rb STOP.json CONTROLLER_STOP.json].map { |n| "BATCH01/#{n}" }
PRODUCT = %w[host_binding input_validator purchase_binding research_result result root_disclosures root_signature scoped_constraints trust_context].map { |n| "BATCH01/source/lib/ap2_mandate_verifier/#{n}.rb" } + ['BATCH01/source/lib/ap2_mandate_verifier.rb']
WORKERS = %w[COMMIT_NOTICE_LOST-commit_hide ABORT_THEN_RETRY-abort_before_commit ABORT_THEN_RETRY-retry INFLIGHT_EMPTY-hold_abort BINDING_CONFLICT-commit_hide].map { |n| "BATCH01/#{n}.stderr" }
INVENTORY = {'dummy'=>['DUMMY/known.txt', 'DUMMY/not-created.txt'], 'prebatch'=>COMMON,
             'batch'=>COMMON+BATCH+PRODUCT+WORKERS}.freeze
paths = INVENTORY.fetch(ARGV.fetch(0))
raise 'arguments' unless ARGV.size == 1
STDOUT.binmode
STDOUT.sync = true
total = 0
present = 0
paths.each do |relative|
  path = ROOT
  missing = false
  st = nil
  relative.split('/').each_with_index do |part, index|
    path = File.join(path, part)
    begin
      st = File.lstat(path)
    rescue Errno::ENOENT
      missing = true
      break
    end
    raise 'symlink refused' if st.symlink?
    raise 'non-directory ancestor' if index < relative.split('/').size-1 && !st.directory?
  end
  if missing
    STDOUT.write("MISSING\t#{relative}\n")
    next
  end
  raise 'nonregular result' unless st.file?
  raise 'result size cap' if st.size > 2*1024*1024 || total + st.size > 32*1024*1024
  File.open(path, File::RDONLY | File::NOFOLLOW | File::NONBLOCK) do |f|
    before = f.stat
    identity = ->(v) { [v.dev,v.ino,v.mode,v.size,v.mtime.to_r,v.ctime.to_r] }
    raise 'result changed before read' unless identity.call(before) == identity.call(st)
    data = f.read(2*1024*1024+1) || ''.b
    raise 'result changed during read' unless data.bytesize == st.size && identity.call(f.stat) == identity.call(before) && identity.call(File.lstat(path)) == identity.call(before)
    sha = Digest::SHA256.hexdigest(data)
    STDOUT.write("FILE\t#{relative}\t#{data.bytesize}\t#{sha}\n")
    STDOUT.write(data)
    STDOUT.write("\n")
    total += data.bytesize
    present += 1
  end
end
STDOUT.write("COMPLETE\t#{paths.size}\t#{present}\t#{total}\n")
