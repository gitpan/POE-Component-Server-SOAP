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
        $kernel->post( soapy => publish => time_server => "dump_body" );
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
        my $params = $soap_transaction->params();
        my $sum = 0;
        while (my ($field, $value) = each(%$params)) {
          $sum += $value;
        }
        $soap_transaction->return("Thanks.  Sum is: $sum");
      },
      dump_body => sub {
        my $soap_transaction = $_[ARG0];
        use YAML qw(freeze);
        $soap_transaction->return(freeze $soap_transaction->params());
      },
    }
  );

$poe_kernel->run();
exit 0;
