#!/bin/sh
#
# $Id$

flunk () {
  echo "$0: $@" >&2
  exit 1
}

srcdir=$(dirname $(realpath $0))
testdir=$srcdir/t
ruby=${RUBY:-$(which ruby)}

initialize () {
    mkdir -p $testdir || flunk "mkdir failed"
    cd $testdir || flunk "cd failed"
    [ $(ls | wc -l) -eq 0 ] || rm -i *
}

setup () {
    (echo aaa; echo bbb; echo ccc) > abc.txt
    (echo AAA; echo BBB; echo CCC) > ABC.txt
    (echo aaa; echo bbb; echo bbb) > abb.txt
    (echo AAA; echo BBB; echo BBB) > ABB.txt
    (echo ccc; echo bbb; echo aaa) > cba.txt
    (echo CCC; echo BBB; echo AAA) > CBA.txt
    (echo a b c) > "a b c.txt"
    (echo c b a) > "c b a.txt"

    ln -s ABC.txt ABC_.txt
    ln -s ABC_.txt ABC__.txt

    for f in *.txt; do
	cp -p "$f" "$f.orig"
    done

    sleep 1
}

teardown () {
    rm *.txt*
}


terminate () {
    cd $srcdir
    rm -rf $testdir
}

inplace () {
    $srcdir/inplace.rb "$@" >/dev/null 2>&1
}

cmp_file () {
    cmp -s "$1" "$2"
}

cmp_time () {
    # Since Ruby's File.stat() does not obtain nanosec for the moment,
    # inplace(1) cannot preserve nanosec values and test(1)'s strict
    # nanosec-wise check does not pass..
    #test ! "$1" -nt "$2" -a ! "$2" -nt "$1"

    $ruby -e 'File.mtime(ARGV[0]) == File.mtime(ARGV[1]) or exit 1' "$1" "$2"
}

test1 () {
    # simple feature test 1 - no argument
    inplace 'sort -r' CBA.txt
    test -e CBA.txt.bak && return 1
    cmp_file CBA.txt CBA.txt.orig || return 1
    cmp_time CBA.txt CBA.txt.orig || return 1

    inplace 'sort -r' abc.txt
    cmp_file abc.txt cba.txt.orig || return 1
    cmp_time abc.txt abc.txt.orig && return 1

    inplace 'tr a-z A-Z' abb.txt
    cmp_file abb.txt ABB.txt.orig || return 1
    cmp_time abb.txt abb.txt.orig && return 1

    inplace 'rev' 'a b c.txt'
    cmp_file 'a b c.txt' 'c b a.txt.orig' || return 1
    cmp_time 'a b c.txt' 'a b c.txt.orig' && return 1

    inplace -e 'sort -r' -e 'tr A-Z a-z' ABC.txt
    cmp_file ABC.txt cba.txt.orig || return 1
    cmp_time ABC.txt cba.txt.orig && return 1

    inplace -t 'sort' cba.txt
    cmp_file cba.txt abc.txt.orig || return 1
    cmp_time cba.txt cba.txt.orig || return 1

    return 0
}

test2 () {
    # simple feature test 2 - 2 arguments
    inplace 'sort -r %1 > %2' CBA.txt
    test -e CBA.txt.bak && return 1
    cmp_file CBA.txt CBA.txt.orig || return 1
    cmp_time CBA.txt CBA.txt.orig || return 1

    inplace 'sort -r %1 > %2' abc.txt
    cmp_file abc.txt cba.txt.orig || return 1
    cmp_time abc.txt abc.txt.orig && return 1

    inplace 'tr a-z A-Z < %1 > %2' abb.txt
    cmp_file abb.txt ABB.txt.orig || return 1
    cmp_time abb.txt abb.txt.orig && return 1

    inplace 'rev %1 > %2' 'a b c.txt'
    cmp_file 'a b c.txt' 'c b a.txt.orig' || return 1
    cmp_time 'a b c.txt' 'a b c.txt.orig' && return 1

    inplace -e 'sort -r %1 > %2' -e 'tr A-Z a-z' ABC.txt
    cmp_file ABC.txt cba.txt.orig || return 1
    cmp_time ABC.txt cba.txt.orig && return 1

    inplace -t 'sort %1 > %2' cba.txt
    cmp_file cba.txt abc.txt.orig || return 1
    cmp_time cba.txt cba.txt.orig || return 1

    return 0
}

test3 () {
    # simple feature test 3 - 1 argument
    inplace "$ruby -i -pe '\$_.upcase!' %1" CBA.txt
    test -e CBA.txt.bak && return 1
    cmp_file CBA.txt CBA.txt.orig || return 1
    cmp_time CBA.txt CBA.txt.orig || return 1

    inplace "$ruby -i -pe '\$_.upcase!' %1" abb.txt
    cmp_file abb.txt ABB.txt.orig || return 1
    cmp_time abb.txt abb.txt.orig && return 1

    inplace "$ruby -i -pe '\$_.chomp!; \$_ = \$_.reverse + \"\\n\"' %1" 'a b c.txt'
    cmp_file 'a b c.txt' 'c b a.txt' || return 1
    cmp_time 'a b c.txt' 'a b c.txt.orig' && return 1

    inplace -e "$ruby -i -pe '\$_.tr!(\"a\", \"A\")' %1" -e "$ruby -i -pe '\$_.tr!(\"bc\", \"BC\")' %1" abc.txt
    cmp_file abc.txt ABC.txt.orig || return 1
    cmp_time abc.txt ABC.txt.orig && return 1

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
    inplace -b.bak 'sort -r' ABC__.txt
    test -e ABC__.txt.bak && return 1
    test -e ABC_.txt.bak && return 1
    test -e ABC.txt.bak && return 1
    cmp_file ABC.txt ABC.txt.orig || return 1
    cmp_time ABC.txt ABC.txt.orig || return 1

    inplace -L -b.bak 'sort -r' ABC__.txt
    test -e ABC__.txt.bak && return 1
    test -e ABC_.txt.bak && return 1
    test -e ABC.txt.bak || return 1
    cmp_file ABC.txt CBA.txt.orig || return 1
    cmp_file ABC.txt.bak ABC.txt.orig || return 1

    return 0
}

main () {
    initialize

    n=7
    error=0

    for i in $(jot 1 $n $n); do
#    for i in $(jot $n 1 $n); do
	echo -n "test$i..."
	setup

	if eval test$i; then
	    echo "ok"
	else
	    echo "failed!"
            error=1
	fi

	teardown
    done

    terminate

    return $error
}

main
