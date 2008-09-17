#!/usr/bin/env ruby
# -*- ruby -*-
#
# inplace.rb - edits files in-place through given filter commands
#
# Copyright (c) 2004, 2005, 2006, 2007, 2008 Akinori MUSHA
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
# $Idaemons: /home/cvs/inplace/inplace.rb,v 1.7 2004/04/21 13:25:51 knu Exp $
# $Id$

if RUBY_VERSION < "1.8.2"
  STDERR.puts "Ruby 1.8.2 or later is required."
  exit 255
end

MYVERSION = "1.2.1"
MYREVISION = %w$Rev$[1]
MYDATE = %w$Date$[1]
MYNAME = File.basename($0)

require "optparse"

def main(argv)
  usage = <<-"EOF"
usage: #{MYNAME} [-Lfinstvz] [-b SUFFIX] COMMANDLINE [file ...]
       #{MYNAME} [-Lfinstvz] [-b SUFFIX] [-e COMMANDLINE] [file ...]
  EOF

  banner = <<-"EOF"
#{MYNAME} - edits files in-place through given filter commands
  version #{MYVERSION} [revision #{MYREVISION}] (#{MYDATE})

#{usage}
  EOF

  filters = []

  $config = Config.new
  file = File.expand_path("~/.inplace")
  $config.load(file) if File.exist?(file)

  opts = OptionParser.new(banner, 24) { |opts|
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

  files = opts.order(*argv)

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
      filtercommand = @formatter.format(origfile, tmpfile)
    else
      filtercommand = @formatter.format(origfile, infile, tmpfile)
    end

    if run(filtercommand)
      if !File.file?(tmpfile)
        flunk origfile, "output file removed"
      end

      if !$accept_empty && File.zero?(tmpfile)
        flunk origfile, "empty output"
      end

      if outfile_is_original && FileUtils.cmp(origfile, tmpfile)
        flunk origfile, "unchanged"
      end

      stat = File.stat(infile)
      newstat = File.stat(tmpfile) if $dry_run

      uninterruptible {
        replace(tmpfile, outfile, stat)
      }

      newstat = File.stat(outfile) unless $dry_run

      info "#{origfile}: edited (%d bytes -> %d bytes)", stat.size, newstat.size
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
      # If chown fails, discard setuid/setgid bits
      mode &= 01777
    end

    debug "chmod: %o %s", stat.mode, file.shellescape
    File.chmod stat.mode, file unless $dry_run
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

if RUBY_VERSION >= "1.8.7"
  require 'shellwords'
else
  class String
    def shellescape
      # An empty argument will be skipped, so return empty quotes.
      return "''" if empty?

      str = dup

      # Process as a single byte sequence because not all shell
      # implementations are multibyte aware.
      str.gsub!(/([^A-Za-z0-9_\-.,:\/@\n])/n, "\\\\\\1")

      # A LF cannot be escaped with a backslash because a backslash + LF
      # combo is regarded as line continuation and simply ignored.
      str.gsub!(/\n/, "'\n'")

      return str
    end
  end

  class Tempfile
    alias orig_make_tmpname make_tmpname

    def make_tmpname(basename, n)
      case basename
      when Array
        prefix, suffix = *basename
        make_tmpname(prefix, n) + suffix
      else
        orig_make_tmpname(basename, n).tr('.', '-')
      end
    end
  end
end

class Config
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

$uninterruptible = false

[:SIGINT, :SIGQUIT, :SIGTERM].each { |sig|
  trap(sig) {
    unless $uninterruptible
      STDERR.puts "Interrupted."
      exit 130
    end
  }
}

def uninterruptible
  orig = $uninterruptible
  $uninterruptible = true

  yield
ensure
  $uninterruptible = orig
end

main(ARGV)
