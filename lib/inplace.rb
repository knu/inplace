#!/usr/bin/env ruby
# -*- ruby -*-
#
# inplace.rb - edits files in-place through given filter commands
#
# Copyright (c) 2004-2023 Akinori MUSHA
#
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
# OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
# SUCH DAMAGE.
#

module Inplace
  VERSION = "1.3.0"
end

MYNAME = File.basename($0)

require "optparse"
require "shellwords"

def main(argv)
  $uninterruptible = $interrupt = false

  [:SIGINT, :SIGQUIT, :SIGTERM].each { |sig|
    trap(sig) {
      if $uninterruptible
        $interrupt = true
      else
        interrupt
      end
    }
  }

  usage = <<-"EOF"
usage: #{MYNAME} [-Lfinstvz] [-b SUFFIX]
                 [-e "COMMANDLINE"] [-E COMMAND ... --] [file ...]
  EOF

  banner = <<-"EOF"
#{MYNAME} version #{Inplace::VERSION}

Edits files in-place through given filter commands.

#{usage}
  EOF

  filters = []

  $config = Inplace::Config.new
  [
    File.join(
      ENV.fetch("XDG_CONFIG_HOME") { File.expand_path("~/.config") },
      "inplace/config"
    ),
    File.expand_path("~/.inplace"),
  ].each do |file|
    if File.exist?(file)
      $config.load(file)
      break
    end
  end

  opts = OptionParser.new(banner, 24) { |opts|
    opts.version = Inplace::VERSION
    nextline = "\n" << opts.summary_indent << " " * opts.summary_width << " "

    opts.on("-h", "--help",
      "Show this message.") {
      print opts
      exit 0
    }

    opts.on("-L", "--dereference",
      "Edit the original file for each symlink.") {
      |b| $dereference = b
    }

    opts.on("-b", "--backup-suffix=SUFFIX",
      "Create a backup file with the SUFFIX for each file." << nextline <<
      "Backup files will be written over existing files," << nextline <<
      "if any.") {
      |s| $backup_suffix = s
    }

    opts.on("-D", "--debug",
      "Turn on debug mode.") {
      |b| $debug = b and $verbose = true
    }

    opts.on("-e", "--execute=COMMANDLINE",
      "Run COMMANDLINE for each file in which the following" << nextline <<
      "placeholders can be used:" << nextline <<
      "  %0: replaced by the original file path" << nextline <<
      "  %1: replaced by the source file path" << nextline <<
      "  %2: replaced by the destination file path" << nextline <<
      "  %%: replaced by a %" << nextline <<
      "Missing %2 indicates %1 is modified destructively," << nextline <<
      "and missing both %1 and %2 implies \"(...) < %1 > %2\"" << nextline <<
      "around the command line.") {
      |s| filters << FileFilter.new($config.expand_alias(s))
    }

    opts.on("-E", "--execute-args[=TERM]",
      "Run COMMAND with all following arguments until TERM" << nextline <<
      "(default: '--') is encountered." << nextline <<
      "This is similar to -e except it takes a list of" << nextline <<
      "arguments.") { |s|
      term = s || '--'
      args = []
      until (arg = argv.shift) == term
        raise "-E must end with #{term}" if arg.nil?

        args << arg
      end
      commandline = args.map { |arg|
        case arg
        when /%/
          arg.gsub(/[^A-Za-z0-9_\-.,:+\/@\n%]/, "\\\\\\&").gsub(/\n/, "'\n'")
        else
          arg.shellescape
        end
      }.join(' ')
      filters << FileFilter.new($config.expand_alias(commandline))
    }

    opts.on("-f", "--force",
      "Force editing even if a file is read-only.") {
      |b| $force = b
    }

    opts.on("-i", "--preserve-inode",
      "Make sure to preserve the inode number of each file.") {
      |b| $preserve_inode = b
    }

    opts.on("-n", "--dry-run",
      "Just show what would have been done.") {
      |b| $dry_run = b and $verbose = true
    }

    opts.on("-s", "--same-directory",
      "Create a temporary file in the same directory as" << nextline <<
      "each replaced file.") {
      |b| $same_directory = b
    }

    opts.on("-t", "--preserve-timestamp",
      "Preserve the modification time of each file.") {
      |b| $preserve_time = b
    }

    opts.on("-v", "--verbose",
      "Turn on verbose mode.") {
      |b| $verbose = b
    }

    opts.on("-z", "--accept-empty",
      "Accept empty (zero-sized) output.") {
      |b| $accept_empty = b
    }
  }

  setup()

  argv = argv.dup
  opts.order!(argv)
  files = argv

  if filters.empty? && !files.empty?
    filters << FileFilter.new($config.expand_alias(files.shift))
  end

  if files.empty?
    STDERR.puts "No files to process given.", ""
    print opts
    exit 2
  end

  case filters.size
  when 0
    STDERR.puts "No filter command line to execute given.", ""
    print opts
    exit 1
  when 1
    filter = filters.first

    files.each { |file|
      begin
        filter.filter!(file, file)
      rescue => e
        STDERR.puts "#{file}: skipped: #{e}"
      end
    }
  else
    files.each { |file|
      tmpfile = FileFilter.make_tmpfile_for(file)

      first, last = 0, filters.size - 1

      begin
        filters.each_with_index { |filter, i|
          if i == first
            filter.filter(file, file, tmpfile)
          elsif i == last
            filter.filter(file, tmpfile, file)
          else
            filter.filter!(file, tmpfile)
          end
        }
      rescue => e
        STDERR.puts "#{file}: skipped: #{e}"
      end
    }
  end
rescue OptionParser::ParseError => e
  STDERR.puts "#{MYNAME}: #{e}", usage
  exit 64
rescue => e
  STDERR.puts "#{MYNAME}: #{e}"
  exit 1
end

def setup
  $backup_suffix = nil
  $debug = $verbose =
    $dereference = $force = $dry_run = $same_directory =
    $preserve_inode = $preserve_time = $accept_empty = false
end

require 'set'
require 'tempfile'
require 'fileutils'
require 'pathname'

class FileFilter
  def initialize(template)
    raise ArgumentError, "empty command" if template.empty?

    @formatter = Formatter.new(template)
  end

  def destructive?
    @formatter.arity == 1
  end

  def filter!(origfile, file)
    filter(origfile, file, file)
  end

  def filter(origfile, infile, outfile)
    if !File.exist?(infile)
      flunk origfile, "file not found"
    end

    outfile_is_original = !tmpfile?(outfile)
    outfile_stat = File.lstat(outfile)

    if outfile_stat.symlink?
      $dereference or
        flunk origfile, "symlink"

      begin
        outfile = Pathname.new(outfile).realpath.to_s
        outfile_stat = File.lstat(outfile)
      rescue => e
        flunk origfile, "symlink unresolvable: %s", e
      end
    end

    outfile_stat.file? or
      flunk origfile, "symlink to a non-regular file"

    $force || outfile_stat.writable? or
      flunk origfile, "symlink to a read-only file"

    tmpfile = FileFilter.make_tmpfile_for(outfile)

    if destructive?
      debug "cp(%s, %s)", infile, tmpfile
      FileUtils.cp(infile, tmpfile)
      command = @formatter.format(origfile, tmpfile)
    else
      command = @formatter.format(origfile, infile, tmpfile)
    end

    if run(command)
      File.file?(tmpfile) or
        flunk origfile, "output file removed"

      !$accept_empty && File.zero?(tmpfile) and
        flunk origfile, "empty output"

      outfile_is_original && FileUtils.identical?(origfile, tmpfile) and
        flunk origfile, "unchanged"

      stat = File.stat(infile)
      newsize = File.size(tmpfile) if $dry_run

      uninterruptible {
        replace(tmpfile, outfile, stat)
      }

      newsize = File.size(outfile) unless $dry_run

      info "%s: edited (%d bytes -> %d bytes)", origfile, stat.size, newsize
    else
      flunk origfile, "command exited with %d", $?.exitstatus
    end
  end

  @@tmpfiles = Set.new

  def tmpfile?(file)
    @@tmpfiles.include?(file)
  end

  TMPNAME_BASE = MYNAME.tr('.', '-')

  def self.make_tmpfile_for(outfile)
    if m = File.basename(outfile).match(/(\..+)$/)
      ext = m[1]
    else
      ext = ''
    end
    if $same_directory
      tmpf = Tempfile.new([TMPNAME_BASE, ext], File.dirname(outfile))
    else
      tmpf = Tempfile.new([TMPNAME_BASE, ext])
    end
    tmpf.close
    path = tmpf.path
    @@tmpfiles << path
    return path
  end

  private
  def debug(fmt, *args)
    puts sprintf(fmt, *args) if $debug || $dry_run
  end

  def info(fmt, *args)
    puts sprintf(fmt, *args) if $verbose
  end

  def warn(fmt, *args)
    STDERR.puts "warning: " + sprintf(fmt, *args)
  end

  def error(fmt, *args)
    STDERR.puts "error: " + sprintf(fmt, *args)
  end

  def flunk(origfile, fmt, *args)
    raise "#{origfile}: " << sprintf(fmt, *args)
  end

  def run(command)
    debug "command: %s", command
    system(command)
  end

  def replace(file1, file2, stat)
    if tmpfile?(file2)
      debug "move: %s -> %s", file1.shellescape, file2.shellescape
      FileUtils.mv(file1, file2)
    else
      if $backup_suffix && !$backup_suffix.empty?
        bakfile = file2 + $backup_suffix

        if $preserve_inode
          debug "copy: %s -> %s", file2.shellescape, bakfile.shellescape
          FileUtils.cp(file2, bakfile, :preserve => true) unless $dry_run 
        else
          debug "move: %s -> %s", file2.shellescape, bakfile.shellescape
          FileUtils.mv(file2, bakfile) unless $dry_run
        end
      end

      begin
        if $preserve_inode
          debug "copy: %s -> %s", file1.shellescape, file2.shellescape
          FileUtils.cp(file1, file2) unless $dry_run
          debug "remove: %s", file1.shellescape
          FileUtils.rm(file1) unless $dry_run
        else
          debug "move: %s -> %s", file1.shellescape, file2.shellescape
          FileUtils.mv(file1, file2) unless $dry_run
        end
      rescue => e
        error "%s: failed to overwrite: %s", file2, e
        error "%s: result file left: %s", file2, file1
        exit! 1
      end
    end

    preserve(file2, stat)
  end

  def preserve(file, stat)
    if $preserve_time
      debug "utime: %s/%s %s",
           stat.atime.strftime("%Y-%m-%dT%T"),
           stat.mtime.strftime("%Y-%m-%dT%T"), file.shellescape
      File.utime stat.atime, stat.mtime, file unless $dry_run
    end

    mode = stat.mode

    begin
      debug "chown: %d:%d %s", stat.uid, stat.gid, file.shellescape
      File.chown stat.uid, stat.gid, file unless $dry_run
    rescue Errno::EPERM
      mode &= 01777
    end

    debug "chmod: %o %s", mode, file.shellescape
    File.chmod mode, file unless $dry_run
  end

  class Formatter
    def initialize(template)
      @template = template.dup

      begin
        self.format("0", "1", "2")
      rescue => e
        raise e
      end

      if @arity == 0
        @template = "(#{@template}) < %1 > %2"
        @arity = 2
      end
    end

    attr_reader :template, :arity

    def format(origfile, infile, outfile = nil)
      s = ''
      template = @template.dup
      arity_bits = 0

      until template.empty?
        template.sub!(/\A([^%]+)/) {
          s << $1
          ''
        }
        template.sub!(/\A%(.)/) {
          case c = $1
          when '%'
            s << c
          when '0'
            s << origfile.shellescape
          when '1'
            s << infile.shellescape
            arity_bits |= 0x1
          when '2'
            s << outfile.shellescape
            arity_bits |= 0x2
          else
            raise ArgumentError, "invalid placeholder specification (%#{c}): #{@template}"
          end
          ''
        }
      end

      case arity_bits
      when 0x0
        @arity = 0
      when 0x1
        @arity = 1
      when 0x2
        raise ArgumentError, "%1 is missing while %2 is specified: #{@template}"
      when 0x3
        @arity = 2
      end

      return s
    end
  end
end

class Inplace::Config
  def initialize
    @alias = {}
  end

  def load(file)
    File.open(file) { |f|
      f.each_line { |line|
        line.strip!
        next if /^#/ =~ line

        if m = line.match(/^([^\s=]+)\s*=\s*(.+)/)
          @alias[m[1]] = m[2]
        end
      }
    }
  end

  def expand_alias(command)
    if @alias.key?(command)
      new_command = @alias[command]

      info "expanding alias: %s: %s\n", command, new_command

      new_command
    else
      command
    end
  end
end

def interrupt
  STDERR.puts "Interrupted."
  exit 130
end

def uninterruptible
  orig = $uninterruptible
  $uninterruptible = true

  yield

  interrupt if $interrupt
ensure
  $uninterruptible = orig
end

if $0 == __FILE__
  main(ARGV)
end
