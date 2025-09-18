INPLACE(1)
==========

## NAME

inplace -- edits files in-place through given filter commands

## SYNOPSIS

```
inplace [-DLfinstvz] [-b SUFFIX]
        [[-e] "COMMANDLINE"] [-E COMMAND ... --] [file ...]
```

## DESCRIPTION

The inplace command is a utility to edit files in-place through given
filter commands preserving the original file attributes.  Mode and
ownership (user and group) are preserved by default, and time (access
and modification) by choice.

Inode numbers will change by default, but there is a `-i` option with
which given the inode number of each edited file will be preserved.

As for filter commands, a single command may be specified as the first
argument to inplace.  To pass many filter commands, use `-e` or `-E`
option.

There are some cases where inplace does not replace a file, such as
when:

1.  The original file is not writable (use `-f` to force editing
    against read-only files)

2.  A filter command fails and exits with a non-zero return code

3.  The resulted output is identical to the original file

4.  The resulted output is empty (use `-z` to accept empty output)

## OPTIONS

The following command line arguments are supported:

*   `-h`
*   `--help`

    Show help and exit.

*   `-D`
*   `--debug`

    Turn on debug output.

*   `-L`
*   `--dereference`

    By default, inplace ignores non-regular files including symlinks,
    but this switch makes it resolve (dereference) each symlink using
    `realpath(3)` and edit the original file.

*   `-b SUFFIX`
*   `--backup-suffix SUFFIX`

    Create a backup file with the given suffix for each file.  Note
    that backup files will be written over existing files, if any.

*   `-e COMMANDLINE`
*   `--execute COMMANDLINE`
*   `-E COMMAND ... --` / `-E<TERM> COMMAND ... <TERM>`
*   `--execute-args COMMAND ... --` / `--execute-args=<TERM> COMMAND ... <TERM>`

    Specify a filter command line to run for each file in which the
    following placeholders can be used:

    *   `%0`

        replaced by the original file path, shell escaped with `\`'s
        as necessary

    *   `%1`

        replaced by the source file path, shell escaped with `\`'s as
        necessary

    *   `%2`

        replaced by the destination file path, shell escaped with
        `\`'s as necessary

    *   `%%`

        replaced by `%`

    Omission of `%2` indicates `%1` should be modified destructively,
    and omission of both `%1` and `%2` implies `(...) < %1 > %2`
    around the command line.

    When the filter command is run, the destination file is always an
    empty temporary file, and the source file is either the original
    file or a temporary copy file.

    Every temporary file has the same suffix as the original file, so
    that file name aware programs can play nicely with it.

    Instead of specifying a whole command line, you can use a command
    alias defined in a configuration file, `~/.config/inplace/config`
    or `~/.inplace`.  See the FILES section for the file format.

    This option can be specified many times, and they will be executed
    in sequence.  A file is only replaced if all of them succeeds.

    See the EXAMPLES section below for details.

*   `-f`
*   `--force`

    By default, inplace does not perform editing if a file is not
    writable.  This switch makes it force editing even if a file to
    process is read-only.

*   `-i`
*   `--preserve-inode`

    Make sure to preserve the inode number of each file.

*   `-n`
*   `--dry-run`

    Do not perform any destructive operation and just show what would
    have been done.  This switch implies `-v`.

*   `-s`
*   `--same-directory`

    Create a temporary file in the same directory as each replaced
    file.  This may speed up the performance when the directory in
    question is on a partition that is fast enough and the system
    temporary directory is slow.

    This switch can be effectively used when the temporary directory
    does not have sufficient disk space for a resulted file.

    If this option is specified, edited files will have newly assigned
    inode numbers.  To prevent this, use the `-i` option.

*   `-t`
*   `--preserve-timestamp`

    Preserve the access and modification times of each file.

*   `-v`
*   `--verbose`

    Turn on verbose mode.

*   `-z`
*   `--accept-empty`

    By default, inplace does not replace the original file when a
    resulted file is empty in size because it is likely that there is
    a mistake in the filter command.  This switch makes it accept
    empty (zero-sized) output and replace the original file with it.

## EXAMPLES

*   Sort files in-place using sort(1):

        inplace sort file1 file2 file3

    Below works the same as above, passing each input file via the
    command line argument:

        inplace 'sort %1 > %2' file1 file2 file3

*   Perform in-place charset conversion and newline code conversion:

        inplace -E iconv -f EUC-JP -t UTF-8 -- -E perl -pe 's/$/\r/' -- file1 file2 file3

*   Process image files taking backup files:

        inplace -b.orig -E convert -rotate 270 -resize 50%% %1 %2 -- *.jpg

*   Perform a mass MP3 tag modification without changing timestamps:

        find mp3/Some_Artist -name '*.mp3' -print0 | \
          xargs -0 inplace -tE mp3info -a "Some Artist" -g "Progressive Rock" %1 --

    As you see above, inplace makes a nice combo with find(1) and
    `xargs(1)`.

## FILES

*   `~/.config/inplace/config` or `~/.inplace`

    The configuration file, which syntax is described as follows:

    *   Each alias definition is a name/value pair separated with an
        `=`, one per line.

    *   White spaces at the beginning or the end of a line, and around
        assignment separators (`=`) are stripped off.

    *   Lines starting with a `#` are ignored.

## ENVIRONMENT

*   `TMPDIR`
*   `TMP`
*   `TEMP`

    Temporary directory candidates where inplace attempts to create
    intermediate output files, in that order.  If none is available
    and writable, `/tmp` is used.  If `-s` is specified, they will not
    be used.

## HOW TO INSTALL

### Via Homebrew (macOS/Linux)

        brew install knu/knu/inplace

### Via RubyGems

        gem install inplace

### Manual Installation

Just copy `lib/inplace.rb` to `/somewhere/in/your/path/inplace`.

## SEE ALSO

[`find(1)`](http://www.freebsd.org/cgi/man.cgi?query=find&sektion=1),
[`xargs(1)`](http://www.freebsd.org/cgi/man.cgi?query=xargs&sektion=1),
[`realpath(3)`](http://www.freebsd.org/cgi/man.cgi?query=realpath&sektion=3)

## HISTORY

The inplace utility was first released on 2 May, 2004.

This utility was written when the author did not feel very happy with
the `-i` option added to `sed(1)` on FreeBSD.

## AUTHORS

Akinori MUSHA <knu@iDaemons.org>

Licensed under the 2-clause BSD license.  See `LICENSE` for details.

Visit [the GitHub repository](https://github.com/knu/inplace) for the
latest information and feedback.

## BUGS

There may always be some bugs.  Use at your own risk.
