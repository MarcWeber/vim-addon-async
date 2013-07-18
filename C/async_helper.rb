# encoding: UTF-8
# author: Marc Weber
# license: same as Vim .c code
#
# same as *.c, but in ruby for portability (goal windows ?)
# next steps use popen3, implment simplse loop with waiting, be done

require "open3"
require "thread"

BUF_SIZE = 259072

SHELL_NAME = "sh"
SHELL = "/bin/sh"

def usage(name)
  puts "%s vim-executable vim-server-name process_id from-vim-file to-vim-file cmd_max_chars cmd\n" % name
end

def simulate_dump_terminal
    columns = 80
    rows = 24
    ENV["TERM"] = "dumb"
    ENV["ROWS"] = 1
    ENV["LINENS"] = 1
    ENV["COLUMNS"] = 1
end

class String
  def vim_quote()
    quoted = self.gsub('\\','\\\\') \
     .gsub("\n","\\n") \
     .gsub("\r","\\r") \
     .gsub("\"","\\\"") \
     # Vim can't handle 0 bytes. So replace them by \n
     .gsub("\0", "\\n")
     "[\"%s\"]" % quoted
  end
end

def send(type, buf)
  my_die("type must not be longer than 4 chars\n") if (type.length > 4)

  quoted = buf.vim_quote

  use_file = quoted.length > $CMD_MAX_CHARS;

  if (use_file)
    File.open($TO_VIM, "wb") { |file| file.write(quoted) }
    command = "async#Receive(\"%s\",\"%s\")" % [$PROCESS_ID, type]
  else
    command = "async#Receive(\"%s\",\"%s\",%s)" % [$PROCESS_ID, type, quoted];
  end

  args = [
    $VIM_EXECUTABLE,
    "--servername",
    $VIM_SERVERNAME,
    "--remote-expr",
    command
  ]
  puts args if $DEBUG

  system(*args)

  puts "waiting for Vim reading data file" if $DEBUG

  sleep 0.2 while File.exist? $TO_VIM
  puts "waiting finished"
end

puts ARGV.inspect
usage(ARGV[0]) if ARGV.length < 8

$VIM_EXECUTABLE = ARGV[0]
$VIM_SERVERNAME = ARGV[1]
$PROCESS_ID     = ARGV[2]
$INPUT_FILE_TO_READ     = ARGV[3] # from Vim to this tool
$TO_VIM        = ARGV[4] # if more than cmd_max_chars were received use a file to pass data to Vim for performance reasons
$CMD_MAX_CHARS = Integer(ARGV[5])
$CMD_TO_RUN     = ARGV[6]
puts ">> #{$CMD_TO_RUN}"


Open3.popen2e($CMD_TO_RUN) do |i,o,ts|
  puts ts
  puts ts.inspect

  # fake pid (TODO how to get it?)
  send("pid", ts.pid.to_s);

  # vim -> prog
  threads = []
  threads << Thread.new do
    while true
      if File.exist? $INPUT_FILE_TO_READ
        input = File.open($INPUT_FILE_TO_READ).read
        puts "got #{input.length} bytes from vim" if $DEBUG

        puts "deleting"
        File.delete $INPUT_FILE_TO_READ

        puts "writing to input"
        i.write input
        puts "writing done"
      end
      # this loop sucks ...
      sleep 0.1
    end
  end

  # prog -> vim
  threads << Thread.new do
    while true
      begin
        to_vim = o.read_nonblock(BUF_SIZE)
        puts "read ok" if  $DEBUG

        if to_vim.size > 0
          puts "sending #{to_vim.length} bytes to vim" if $DEBUG
          send("data", to_vim) 
        end

      rescue IO::EAGAINWaitReadable
        to_vim = ""
        puts "would block" if $DEBUG
      end
      sleep 0.1
    end
  end

  puts "joining"
  threads.each {|v| v.join }

  send("died", wait_thr.value.to_s)
end
