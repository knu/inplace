#!/usr/bin/env ruby
# -*- ruby -*-
#
# inplace.rb - edits files in-place through a given filter command
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

if RUBY_VERSION < "1.8.0"
  STDERR.puts "Ruby 1.8 or later is required."
  exit 255
end

RCS_ID = %q$Idaemons$
RCS_REVISION = RCS_ID.split[2]
MYNAME = File.basename($0)

require "optparse"

COLUMNSIZE = 24
NEXTLINE = "\n%*s" % [4 + COLUMNSIZE + 1, '']

def init
  $backup_suffix = ".orig"
  $dereference = $dry_run = $same_directory =
                 $preserve_time = $accept_zero = false
  $commandline = nil
end

def main(argv)
  usage = <<-"EOF"
usage: #{MYNAME} [-Lnstvz] [-b SUFFIX] -e COMMANDLINE [ ...]
  EOF

  banner = <<-"EOF"
#{MYNAME} rev.#{RCS_REVISION} - edits files in-place through a given filter command

#{usage}
  EOF

  opts = OptionParser.new(banner, COLUMNSIZE) { |opts|
    opts.def_option("-h", "--help",
                    "Show this message") {
      print opts
      exit 0
    }

    opts.def_option("-L", "--dereference",
                    "Dereference using realpath(3) and edit the original#{NEXTLINE}file for each symlink") {
      |b|
      $dereference = s
    }

    opts.def_option("-b", "--backup-suffix=SUFFIX",
                    "Create a backup file with the SUFFIX for each file;#{NEXTLINE}Backup files will be written over existing files,#{NEXTLINE}if any") {
      |s|
      $backup_suffix = s
    }

    opts.def_option("-e", "--execute=COMMANDLINE",
                    "Run COMMANDLINE for each file; no %s implies#{NEXTLINE}\"(...) < %s > %s\" around, and one %s implies#{NEXTLINE}\"(...) > %s\" around; %s's will be replaced with#{NEXTLINE}each source file and target file") {
      |s|
      $commandline = s
    }

    opts.def_option("-n", "--dry-run",
                    "Just show what would have been done") {
      |b|
      $dry_run = b and $verbose = true
    }

    opts.def_option("-s", "--same-directory",
                    "Create a temporary file in the same directory as#{NEXTLINE}each replaced file") {
      |b|
      $same_directory = b
    }

    opts.def_option("-t", "--preserve-timestamp",
                    "Preserve the modification time of each file") {
      |b|
      $preserve_time = b
    }

    opts.def_option("-v", "--verbose",
                    "Turn on verbose mode") {
      |b|
      $verbose = b
    }

    opts.def_option("-z", "--accept-empty",
                    "Accept empty (zero-sized) output") {
      |b|
      $accept_zero = b
    }
  }

  init()

  files = opts.order(*argv)

  if $commandline.nil?
    STDERR.puts "No command line to execute given."
    print opts
    exit 1
  end

  filter = FileFilter.new($commandline)

  files.each { |file|
    filter.filter(file)
  }
rescue OptionParser::ParseError => e
  STDERR.puts "#{MYNAME}: #{e}", usage
  exit 64
end

require 'tempfile'
require 'fileutils'

class FileFilter
  def initialize(commandline)
    @commandline = commandline.dup

    case format_arity(@commandline)
    when 0
      @commandline = "(#{@commandline}) < %s > %s"
    when 1
      @commandline = "(#{@commandline}) > %s"
    when 2
      # ok
    else
      raise ArgumentError, "too many arguments: " << commandline
    end
  end

  def filter(infile)
    outfile = nil

    if !File.exist?(infile)
      warn "no such file or directory: %s", infile
      return
    end

    if File.symlink?(infile)
      if !$dereference
        warn "skipping a symlink %s", infile
        return
      end

      if !$have_realpath
        warn "skipping a symlink %s because realpath(3) is unavailable", infile
        return
      end

      outfile = File.realpath(infile)

      if !outfile
        warn "skipping a symlink %s which cannot be resolved", infile
        return
      end

      if !File.file?(outfile)
        warn "skipping a symlink %s which is not linked to a regular file", infile
        return
      end
    else
      if !File.file?(infile)
        warn "skipping %s which is not a regular file", infile
        return
      end

      outfile = infile
    end

    tmpfile = mktemp_for(outfile)

    filtercommand = sprintf(@commandline, sh_escape(infile), sh_escape(tmpfile))

    if run(filtercommand)
      if !File.file?(tmpfile)
        warn "not replacing %s as the output file is gone somehow", infile
        return
      end

      if !$accept_zero && File.zero?(tmpfile)
        warn "not replacing %s as the output file is empty", infile
        return
      end unless $dry_run

      stat = File.stat(infile)

      replace(tmpfile, outfile, stat)
    else
      warn "not replacing %s as the command exited with %d", infile, $?.exitstatus
      return
    end
  end

  private
  def format_arity(fmt)
    args = []

    # 5 should be enough here
    5.times { |i|
      begin
        format(fmt, *args)
        return i
      rescue ArgumentError => e
        if /^too few argument/ =~ e.message
          args.push(0)
          next
        end

        raise e
      end
    }
  end

  def sh_escape(str)
    str.gsub(/([^A-Za-z0-9_\-.,:\/@])/n, "\\\\\\1")
  end

  def info(fmt, *args)
    puts sprintf(fmt, *args) if $verbose
  end

  def warn(fmt, *args)
    STDERR.puts "warning: " + sprintf(fmt, *args)
  end

  def mktemp_for(outfile)
    if $same_directory
      f = Tempfile.new(MYNAME, File.dirname(outfile))
    else
      f = Tempfile.new(MYNAME)
    end

    f.close
    f.path
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
