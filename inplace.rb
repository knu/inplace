#!/usr/bin/env ruby
# -*- ruby -*-
#
# inplace.rb - edits files in-place through given filter commands
#
# Copyright (c) 2004 Akinori MUSHA
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

if RUBY_VERSION < "1.8.0"
  STDERR.puts "Ruby 1.8 or later is required."
  exit 255
end

MYVERSION = "1.0.1"
MYREVISION = %w$Rev$[1]
MYDATE = %w$Date$[1]
MYNAME = File.basename($0)

require "optparse"

COLUMNSIZE = 24
NEXTLINE = "\n%*s" % [4 + COLUMNSIZE + 1, '']

def init
  $backup_suffix = nil
  $dereference = $dry_run = $same_directory =
                 $preserve_time = $accept_zero = false
  $filters = []
end

def main(argv)
  usage = <<-"EOF"
usage: #{MYNAME} [-Lnstvz] [-b SUFFIX] COMMANDLINE [file ...]
       #{MYNAME} [-Lnstvz] [-b SUFFIX] [-e COMMANDLINE] [file ...]
  EOF

  banner = <<-"EOF"
#{MYNAME} - edits files in-place through given filter commands
  version #{MYVERSION} [revision #{MYREVISION}] (#{MYDATE})

#{usage}
  EOF

  opts = OptionParser.new(banner, COLUMNSIZE) { |opts|
    opts.def_option("-h", "--help",
                    "Show this message.") {
      print opts
      exit 0
    }

    opts.def_option("-L", "--dereference",
                    "Dereference using realpath(3) and edit the original#{NEXTLINE}file for each symlink.") {
      |b|
      $dereference = b
    }

    opts.def_option("-b", "--backup-suffix=SUFFIX",
                    "Create a backup file with the SUFFIX for each file.#{NEXTLINE}Backup files will be written over existing files,#{NEXTLINE}if any.") {
      |s|
      $backup_suffix = s
    }

    opts.def_option("-e", "--execute=COMMANDLINE",
                    "Run COMMANDLINE for each file in which the following#{NEXTLINE}placeholders can be used:#{NEXTLINE}  %0: replaced by the original file path#{NEXTLINE}  %1: replaced by the source file path#{NEXTLINE}  %2: replaced by the destination file path#{NEXTLINE}  %%: replaced by a %#{NEXTLINE}Missing %2 indicates %1 is modified destructively,#{NEXTLINE}and missing both %1 and %2 implies \"(...) < %1 > %2\"#{NEXTLINE}around the command line.") {
      |s|
      $filters << FileFilter.new(s)
    }

    opts.def_option("-n", "--dry-run",
                    "Just show what would have been done.") {
      |b|
      $dry_run = b and $verbose = true
    }

    opts.def_option("-s", "--same-directory",
                    "Create a temporary file in the same directory as#{NEXTLINE}each replaced file.") {
      |b|
      $same_directory = b
    }

    opts.def_option("-t", "--preserve-timestamp",
                    "Preserve the modification time of each file.") {
      |b|
      $preserve_time = b
    }

    opts.def_option("-v", "--verbose",
                    "Turn on verbose mode.") {
      |b|
      $verbose = b
    }

    opts.def_option("-z", "--accept-empty",
                    "Accept empty (zero-sized) output.") {
      |b|
      $accept_zero = b
    }
  }

  init()

  files = opts.order(*argv)

  if $filters.empty? && !files.empty?
    $filters << FileFilter.new(files.shift)
  end

  if files.empty?
    STDERR.puts "No files to process given.", ""
    print opts
    exit 2
  end

  case $filters.size
  when 0
    STDERR.puts "No filter command line to execute given.", ""
    print opts
    exit 1
  when 1
    filter = $filters.first

    files.each { |file|
      begin
        filter.filter!(file, file)
      rescue => e
        STDERR.puts "#{file}: skipped: #{e}"
      end
    }
  else
    files.each { |file|
      tmpf = FileFilter.mktemp_for(file)
      tmpf.close

      tmpfile = tmpf.path

      first, last = 0, $filters.size - 1

      begin
        $filters.each_with_index { |filter, i|
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

require 'tempfile'
require 'fileutils'

class FileFilter
  def initialize(commandline)
    @formatter = Formatter.new(commandline)
  end

  def destructive?
    @formatter.arity == 1
  end

  def flunk(origfile, fmt, *args)
    raise "#{origfile}: " << sprintf(fmt, *args)
  end

  def filter!(origfile, file)
    filter(origfile, file, file)
  end

  def filter(origfile, infile, outfile)
    if !File.exist?(infile)
      flunk origfile, "file not found"
    end

    if File.symlink?(outfile)
      if !$dereference
        flunk origfile, "symlink"
      end

      if !$have_realpath
        flunk origfile, "symlink; realpath(3) is required to handle it"
      end

      outfile = File.realpath(outfile)

      if !outfile
        flunk origfile, "symlink unresolvable"
      end

      if !File.file?(outfile)
        flunk origfile, "symlink to a non-regular file"
      end
    else
      if !File.file?(outfile)
        flunk origfile, "not a regular file"
      end
    end

    tmpf = FileFilter.mktemp_for(outfile)
    tmpf.close
    tmpfile = tmpf.path

    if destructive?
      info "cp(%s, %s)", infile, tmpfile
      FileUtils.cp(infile, tmpfile) unless $dry_run
      filtercommand = @formatter.format(origfile, tmpfile)
    else
      filtercommand = @formatter.format(origfile, infile, tmpfile)
    end

    if run(filtercommand)
      if !File.file?(tmpfile)
        flunk origfile, "output file removed"
      end

      if !$accept_zero && File.zero?(tmpfile)
        flunk origfile, "empty output"
      end unless $dry_run

      if FileUtils.cmp(infile, tmpfile)
        flunk origfile, "unchanged"
      end unless $dry_run

      stat = File.stat(infile)

      replace(tmpfile, outfile, stat)
    else
      flunk origfile, "command exited with %d", $?.exitstatus
    end
  end

  def self.mktemp_for(outfile)
    if $same_directory
      Tempfile.new(MYNAME, File.dirname(outfile))
    else
      Tempfile.new(MYNAME)
    end
  end

  private
  def info(fmt, *args)
    puts sprintf(fmt, *args) if $verbose
  end

  def warn(fmt, *args)
    STDERR.puts "warning: " + sprintf(fmt, *args)
  end

  def run(command)
    info "system(%s)", command
    $dry_run or system(command)
  end

  def replace(file1, file2, stat)
    if $backup_suffix && !$backup_suffix.empty?
      bakfile = file2 + $backup_suffix

      info "mv(%s, %s)", file2, bakfile
      FileUtils.mv(file2, bakfile) unless $dry_run 
    end

    info "mv(%s, %s)", file1, file2
    FileUtils.mv(file1, file2) unless $dry_run

    preserve(file2, stat)
  end

  def preserve(file, stat)
    if $preserve_time
      info "utime(%s, %s, %s)",
           stat.atime.strftime("%Y-%m-%d %T"),
           stat.mtime.strftime("%Y-%m-%d %T"), file
      File.utime stat.atime, stat.mtime, file unless $dry_run
    end

    mode = stat.mode

    begin
      info "chown(%d, %d, %s)", stat.uid, stat.gid, file
      File.chown stat.uid, stat.gid, file unless $dry_run
    rescue Errno::EPERM
      # If chown fails, we must give up with setuid/setgid bits
      mode &= 01777
    end

    info "chmod(%o, %s)", stat.mode & 01777, file
    File.chmod stat.mode, file unless $dry_run
  end

  class Formatter
    def initialize(fmt)
      @fmt = fmt.dup.freeze
      @arity = nil

      begin
        self.format("0", "1", "2")
      rescue => e
        raise e
      end

      if @arity == 0
        @fmt = "(#{@fmt}) < %1 > %2"
        @arity = 2
      end
    end

    attr_reader :arity

    def format(origfile, infile, outfile = nil)
      s = ''
      fmt = @fmt.dup

      arity_bits = 0

      until fmt.empty?
        fmt.sub!(/\A([^%]+)/) {
          s << $1
          ''
        }
        fmt.sub!(/\A%(.)/) {
          case c = $1
          when '%'
            s << c
          when '0'
            s << sh_escape(origfile)
          when '1'
            s << sh_escape(infile)

            arity_bits |= 0x1
          when '2'
            s << sh_escape(outfile)
            arity_bits |= 0x2
          else
            raise ArgumentError, "invalid placeholder specification (%#{c}): #{@fmt}"
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
        raise ArgumentError, "%1 is missing while %2 is specified: #{@fmt}"
      when 0x3
        @arity = 2
      end

      s
    end

    def sh_escape(str)
      str.gsub(/([^A-Za-z0-9_\-.,:\/@])/n, "\\\\\\1")
    end
  end
end

class File
  begin
    require 'dl/import'
  
    module LIBC
      PATH_MAX = 1024

      extend DL::Importable
      dlload "libc.so"
      extern "char *realpath(char *, char *)"
    end
  
    def File.realpath(path)
      return LIBC.realpath(path, "\0" * LIBC::PATH_MAX)
    end

    $have_realpath = true
  rescue LoadError, RuntimeError
    $have_realpath = false
  end
end

main(ARGV)
