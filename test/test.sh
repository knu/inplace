#!/bin/sh
#
# $Id$

flunk () {
    echo "$0: $@" >&2
    exit 1
}

srcdir="$(cd "$(dirname "$0")"/.. && pwd)" || exit 1
testdir=$srcdir/test/t
ruby=${RUBY:-$(which ruby)}

while getopts d opt; do
    case "$opt" in
	d)
	    debug=1
	    ;;
    esac
done

shift $(($OPTIND - 1))

initialize () {
    mkdir -p $testdir || flunk "mkdir failed"
    cd $testdir || flunk "cd failed"
    [ $(ls | wc -l) -eq 0 ] || rm -i *
}

setup () {
    (echo aaa; echo bbb; echo ccc) > abc.txt
    (echo AAA; echo BBB; echo CCC) > _ABC_.txt
    (echo aaa; echo bbb; echo bbb) > abb.txt
    (echo AAA; echo BBB; echo BBB) > _ABB_.txt
    (echo ccc; echo bbb; echo aaa) > cba.txt
    (echo CCC; echo BBB; echo AAA) > _CBA_.txt
    (echo a b c) > "a b c.txt"
    (echo c b a) > "c b a.txt"

    ln -s _ABC_.txt _ABC_l.txt
    ln -s _ABC_l.txt _ABC_ll.txt

    for f in *.txt; do
	cp -p "$f" "$f.orig"
    done

    sleep 1
}

teardown () {
    rm *.txt*
}

debug () {
    if [ "$debug" = 1 ]; then
        echo "debug: $@" >&2
    fi
}

terminate () {
    cd $srcdir
    rm -rf $testdir
}

inplace_flags=

inplace () {
    local file i1 i2 has_i
    has_i=0

    file="$($ruby -e 'puts ARGV.last' -- "$@")"
    i1="$(inode_of "$file")"
    $srcdir/lib/inplace.rb $inplace_flags "$@" >/dev/null 2>&1
    i2="$(inode_of "$file")"

    if echo " $inplace_flags" | fgrep -qe " -i"; then
        has_i=1
    fi

    if [ $has_i = 1 -a "$i1" != "$i2" ]; then
        echo "inode changed!" >&2
    fi
}

inode_of () {
    expr "$(ls -i "$@")" : '\([0-9]*\)'
}

cmp_file () {
    if cmp -s "$1" "$2"; then
        debug "$1 == $2"
        return 0
    else
        debug "$1 != $2"
        return 1
    fi
}

cmp_time () {
    # Use ruby to compare timestamps ignoring a sub-microsecond
    # difference.

    #test ! "$1" -nt "$2" -a ! "$2" -nt "$1"

    if $ruby -e 'exit !!ARGV.map{|f|m=File.mtime(f);m.to_a<<m.usec}.uniq!' "$1" "$2"; then
        debug "mtime($1) == mtime($2)"
        return 0
    else
        debug "mtime($1) != mtime($2)"
        return 1
    fi
}

test1 () {
    # simple feature test 1 - no argument
    inplace 'sort -r' _CBA_.txt
    test -e _CBA_.txt.bak && return 1
    cmp_file _CBA_.txt _CBA_.txt.orig || return 1
    cmp_time _CBA_.txt _CBA_.txt.orig || return 1

    inplace 'sort -r' abc.txt
    cmp_file abc.txt cba.txt.orig || return 1
    cmp_time abc.txt abc.txt.orig && return 1

    inplace 'tr a-z A-Z' abb.txt
    cmp_file abb.txt _ABB_.txt.orig || return 1
    cmp_time abb.txt abb.txt.orig && return 1

    inplace 'rev' 'a b c.txt'
    cmp_file 'a b c.txt' 'c b a.txt.orig' || return 1
    cmp_time 'a b c.txt' 'a b c.txt.orig' && return 1

    inplace -e 'sort -r' -e 'tr A-Z a-z' _ABC_.txt
    cmp_file _ABC_.txt cba.txt.orig || return 1
    cmp_time _ABC_.txt cba.txt.orig && return 1

    inplace -t 'sort' cba.txt
    cmp_file cba.txt abc.txt.orig || return 1
    cmp_time cba.txt cba.txt.orig || return 1

    return 0
}

test2 () {
    # simple feature test 2 - 2 arguments
    inplace 'sort -r %1 > %2' _CBA_.txt
    test -e _CBA_.txt.bak && return 1
    cmp_file _CBA_.txt _CBA_.txt.orig || return 1
    cmp_time _CBA_.txt _CBA_.txt.orig || return 1

    inplace 'sort -r %1 > %2' abc.txt
    cmp_file abc.txt cba.txt.orig || return 1
    cmp_time abc.txt abc.txt.orig && return 1

    inplace 'tr a-z A-Z < %1 > %2' abb.txt
    cmp_file abb.txt _ABB_.txt.orig || return 1
    cmp_time abb.txt abb.txt.orig && return 1

    inplace 'rev %1 > %2' 'a b c.txt'
    cmp_file 'a b c.txt' 'c b a.txt.orig' || return 1
    cmp_time 'a b c.txt' 'a b c.txt.orig' && return 1

    inplace -e 'sort -r %1 > %2' -e 'tr A-Z a-z' _ABC_.txt
    cmp_file _ABC_.txt cba.txt.orig || return 1
    cmp_time _ABC_.txt cba.txt.orig && return 1

    inplace -t 'sort %1 > %2' cba.txt
    cmp_file cba.txt abc.txt.orig || return 1
    cmp_time cba.txt cba.txt.orig || return 1

    return 0
}

test3 () {
    # simple feature test 3 - 1 argument
    inplace "$ruby -i -pe '\$_.upcase!' %1" _CBA_.txt
    test -e _CBA_.txt.bak && return 1
    cmp_file _CBA_.txt _CBA_.txt.orig || return 1
    cmp_time _CBA_.txt _CBA_.txt.orig || return 1

    inplace "$ruby -i -pe '\$_.upcase!' %1" abb.txt
    cmp_file abb.txt _ABB_.txt.orig || return 1
    cmp_time abb.txt abb.txt.orig && return 1

    inplace "$ruby -i -pe '\$_.chomp!; \$_ = \$_.reverse + \"\\n\"' %1" 'a b c.txt'
    cmp_file 'a b c.txt' 'c b a.txt' || return 1
    cmp_time 'a b c.txt' 'a b c.txt.orig' && return 1

    inplace -e "$ruby -i -pe '\$_.tr!(\"a\", \"A\")' %1" -e "$ruby -i -pe '\$_.tr!(\"bc\", \"BC\")' %1" abc.txt
    cmp_file abc.txt _ABC_.txt.orig || return 1
    cmp_time abc.txt _ABC_.txt.orig && return 1

    return 0
}

test4 () {
    # backup test
    inplace -b.bak 'sort -r' abc.txt
    cmp_file abc.txt cba.txt.orig || return 1
    cmp_file abc.txt.bak abc.txt.orig || return 1
    cmp_time abc.txt abc.txt.orig && return 1
    cmp_time abc.txt.bak abc.txt.orig || return 1

    inplace -b.bak -t 'sort' cba.txt
    cmp_file cba.txt abc.txt.orig || return 1
    cmp_file cba.txt.bak cba.txt.orig || return 1
    cmp_time cba.txt cba.txt.orig || return 1
    cmp_time cba.txt.bak cba.txt.orig || return 1

    return 0
}

test5 () {
    # error test
    inplace -b.bak 'sort -r; exit 1' abc.txt
    test -e abc.txt.bak && return 1
    cmp_file abc.txt abc.txt.orig || return 1
    cmp_time abc.txt abc.txt.orig || return 1

    inplace -b.bak -e 'sort' -e 'exit 1' -e 'tr a-z A-Z' cba.txt
    test -e cba.txt.bak && return 1
    cmp_file cba.txt cba.txt.orig || return 1
    cmp_time cba.txt cba.txt.orig || return 1
}

test6 () {
    # zero-sized output test
    inplace -b.bak 'cat /dev/null' abb.txt
    test -e abb.txt.bak && return 1
    cmp_file abb.txt abb.txt.orig || return 1
    cmp_time abb.txt abb.txt.orig || return 1

    inplace -z -b.bak 'cat /dev/null' abb.txt
    test -s abb.txt && return 1
    cmp_file abb.txt.bak abb.txt.orig || return 1
    cmp_time abb.txt.bak abb.txt.orig || return 1

    return 0
}

test7 () {
    # symlink test
    inplace -b.bak 'sort -r' _ABC_ll.txt
    test -e _ABC_ll.txt.bak && return 1
    test -e _ABC_l.txt.bak && return 1
    test -e _ABC_.txt.bak && return 1
    cmp_file _ABC_.txt _ABC_.txt.orig || return 1
    cmp_time _ABC_.txt _ABC_.txt.orig || return 1

    inplace -L -b.bak 'sort -r' _ABC_ll.txt
    test -e _ABC_ll.txt.bak && return 1
    test -e _ABC_l.txt.bak && return 1
    test -e _ABC_.txt.bak || return 1
    cmp_file _ABC_.txt _CBA_.txt.orig || return 1
    cmp_file _ABC_.txt.bak _ABC_.txt.orig || return 1

    return 0
}

main () {
    initialize

    n=7
    error=0

    for inplace_flags in '' '-s' '-i' '-i -s'; do
        for i in $(jot $n 1 $n); do
	    if [ X"$inplace_flags" != X"" ]; then
                printf "%s with %s..." "test$i" "$inplace_flags"
            else
	        printf "%s..." "test$i"
            fi

	    setup

	    if eval test$i; then
	        echo "ok"
	    else
	        echo "failed!"
                error=1
	    fi

	    teardown
        done
    done

    terminate

    return $error
}

main
