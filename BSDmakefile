# $Idaemons: /home/cvs/inplace/BSDmakefile,v 1.1 2004/04/07 09:07:46 knu Exp $
# $Id$

PREFIX?=	/usr/local
BINDIR=		${PREFIX}/bin
MANPREFIX?=	${PREFIX}
MANDIR=		${MANPREFIX}/man/man

SCRIPTS=	inplace.rb
MAN=		inplace.1

.PATH:	${.CURDIR}/..

.include <bsd.prog.mk>

test:
	@${.CURDIR}/test.sh
