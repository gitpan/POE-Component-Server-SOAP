#!/usr/bin/perl
# $Id: Makefile.PL,v 1.1 2002/09/06 21:54:25 rcaputo Exp $

use strict;
use lib qw(./mylib);
use ExtUtils::MakeMaker;

# Ensure that ./CHANGES exists.
open(CHANGES, ">>CHANGES");
close CHANGES;

# Write that makefile.
WriteMakefile
  ( NAME         => 'POE::Component::Server::SOAP',
    AUTHOR       => 'Rocco Caputo <rcaputo@cpan.org>',
    ABSTRACT     => 'POE component for providing SOAP services.',
    VERSION_FROM => 'SOAP.pm',
    PM           => { 'SOAP.pm' => '$(INST_LIBDIR)/SOAP.pm',
                    },
    PREREQ_PM    => { 'POE'                          => 0.22,
                      'SOAP::EnvelopeMaker'          => 0.28,
                      'POE::Component::Server::HTTP' => 0.02,
                    },
    dist         =>
    { COMPRESS   => 'gzip -9f',
      SUFFIX     => 'gz',
      PREOP      => ( 'cvs-log.perl | ' .
                      'tee ./$(DISTNAME)-$(VERSION)/CHANGES > ./CHANGES'
                    ),
    },
  );
