# frozen_string_literal: true
require "tmpdir"
require_relative "stage7_saved_replay_test"
module Stage11IOTest
  def self.reject
    yield
    raise "unsafe read accepted"
  rescue RuntimeError => error
    raise if error.message == "unsafe read accepted"
  end
  def self.run
    count = 0
    Dir.mktmpdir("stage11-io-") do |dir|
      path = File.join(dir, "input")
      File.binwrite(path, "abcd")
      raise unless Stage7SavedReplayTest.bounded_regular(path, 8) == "abcd"; count += 1
      File.binwrite(path, "x" * 9)
      reject { Stage7SavedReplayTest.bounded_regular(path, 8) }; count += 1
      File.binwrite(path, "abcd")
      link = File.join(dir, "link"); File.symlink(path, link)
      reject { Stage7SavedReplayTest.bounded_regular(link, 8) }; count += 1
      fifo = File.join(dir, "fifo"); File.mkfifo(fifo)
      reject { Stage7SavedReplayTest.bounded_regular(fifo, 8) }; count += 1
      original = File.method(:open)
      begin
        File.define_singleton_method(:open) do |*args, &block|
          replacement = File.join(dir, "replacement"); File.binwrite(replacement, "wxyz")
          File.rename(replacement, path)
          original.call(*args, &block)
        end
        reject { Stage7SavedReplayTest.bounded_regular(path, 8) }; count += 1
      ensure
        File.define_singleton_method(:open, original)
      end
      File.binwrite(path, "abcd")
      requested = nil
      begin
        File.define_singleton_method(:open) do |*args, &block|
          original.call(*args) do |file|
            read = file.method(:read)
            file.define_singleton_method(:read) do |limit|
              requested = limit
              File.write(path, "x" * 65_536, mode: "a")
              read.call(limit)
            end
            block.call(file)
          end
        end
        reject { Stage7SavedReplayTest.bounded_regular(path, 8) }; count += 1
      ensure
        File.define_singleton_method(:open, original)
      end
      raise "read cap bypass" unless requested == 9; count += 1
    end
    puts "PASS #{count} Ruby saved-fixture read controls; bounded descriptor; no fixture generation"
  end
end
Stage11IOTest.run if $PROGRAM_NAME == __FILE__
