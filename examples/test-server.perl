#!/usr/bin/perl

use warnings;
use strict;

use POE;

use lib qw(blib/lib);
use POE::Component::Server::SOAP;

POE::Component::Server::SOAP->new( alias => "soapy", port  => 32080 );

POE::Session->create
  ( inline_states =>
    { _start => sub {
        my $kernel = $_[KERNEL];
        $kernel->alias_set("time_server");
        $kernel->post( soapy => publish => time_server => "get_localtime" );
        $kernel->post( soapy => publish => time_server => "sum_things" );
      },
      get_localtime => sub {
        my $soap_transaction = $_[ARG0];
        $soap_transaction->return("Local server time is: " . localtime());
      },
      get_gmtime => sub {
        my $soap_transaction = $_[ARG0];
        $soap_transaction->return("Greenwich Mean time is: " . gmtime());
      },
      sum_things => sub {
        my $soap_transaction = $_[ARG0];
        my $sum = 0;
        foreach ($soap_transaction->params()) {
          $sum += $_;
        }
        $soap_transaction->return("Thanks.  Sum is: $sum");
      },
    }
  );

$poe_kernel->run();
exit 0;
