# $Id: SOAP.pm,v 1.4 2002/09/09 03:44:40 rcaputo Exp $
# License and documentation are after __END__.

package POE::Component::Server::SOAP;

use warnings;
use strict;
use Carp qw(croak);

use vars qw($VERSION);
$VERSION = '0.03';

use POE;
use POE::Component::Server::HTTP;
use SOAP::Defs;
use SOAP::EnvelopeMaker;
use SOAP::Parser;

my %public_interfaces;

sub new {
  my $type = shift;

  croak "Must specify an even number of parameters to $type\->new()" if @_ % 2;
  my %params = @_;

  my $alias = delete $params{alias};
  croak "Must specify an alias in $type\->new()"
    unless defined $alias and length $alias;

  my $interface = delete $params{interface};
  croak "$type\->new() currently does not support the interface parameter"
    if defined $interface;

  my $port = delete $params{port};
  $port = 80 unless $port;

  POE::Session->create
    ( inline_states =>
      { _start => sub {
          $_[KERNEL]->alias_set($alias);
        },
        publish => sub {
          my ($alias, $event) = @_[ARG0, ARG1];
          $public_interfaces{$alias}{$event} = 1;
        },
        rescind => sub {
          my ($alias, $event) = @_[ARG0, ARG1];
          delete $public_interfaces{$alias}{$event};
        },
      }
    );

  POE::Component::Server::HTTP->new
    ( Port     => $port,
      Headers  =>
      { Server => "POE::Component::Server::SOAP/$VERSION",
      },
      ContentHandler => { "/" => \&web_handler },
    );

  undef;
}

### Handle web requests by farming them out to other sessions.

sub web_handler {
  my ($request, $response) = @_;

  # Parse useful things from the request.

  my $query_string = $request->uri->query();
  unless (defined($query_string) and $query_string =~ /\bsession=(.+ $ )/x) {
    $response->code(400);
    return RC_OK;
  }
  my $session = $1;

  my $http_method            = $request->method();
  my $request_content_type   = $request->header('Content-Type');
  my $request_content_length = $request->header('Content-Length');
  my $soap_method_name       = $request->header('SOAPAction');
  my $debug_request          = $request->header('DebugRequest');
  my $request_content        = $request->content();

  unless ($request_content_type =~ /^text\/xml(;.*)?$/) {
    _request_failed( $response,
                     $soap_fc_client,
                     "Bad Request",
                     "Content-Type must be text/xml.",
                   );
    return RC_OK;
  }

  unless (defined($soap_method_name) and length($soap_method_name)) {
    _request_failed( $response,
                     $soap_fc_client,
                     "Bad Request",
                     "SOAPAction is required.",
                   );
    return RC_OK;
  }

  unless ($soap_method_name =~ /^([\"\']?)(\S+)\#(\S+)\1$/) {
   _request_failed( $response,
                    $soap_fc_client,
                    "Bad Request",
                    "Unrecognized SOAPAction header: $soap_method_name",
                  );
  }
  my ($event_uri, $event_name) = ($2, $3);

  my ($headers, $body);
  eval {
    my $soap_parser = SOAP::Parser->new();
    $soap_parser->parsestring($request_content);
    $headers = $soap_parser->get_headers();
    $body    = $soap_parser->get_body();
  };
  if ($@) {
    _request_failed( $response,
                     $soap_fc_server,
                     "Application Faulted",
                     "Failed while unmarshaling the request: $@",
                   );
    return RC_OK;
  }
  if (length($body) == 0) {
    _request_failed( $response,
                     $soap_fc_server,
                     "Application Faulted",
                     "Failed while unmarshaling the request: Empty body.",
                   );
    return RC_OK;
  }

  unless (exists $public_interfaces{$session}) {
    _request_failed( $response,
                     $soap_fc_client,
                     "Bad Request",
                     "Unknown session: $session",
                   );
    return RC_OK;
  }

  unless (exists $public_interfaces{$session}{$event_name}) {
    _request_failed( $response,
                     $soap_fc_client,
                     "Bad Request",
                     "Unknown event: $event_name",
                   );
    return RC_OK;
  }

  eval {
    SoapTransaction->start($response, $session, $event_name, $headers, $body);
  };
  if ($@) {
    _request_failed( $response,
                     $soap_fc_server,
                     "Application Faulted",
                     "An exception fired while processing the request: $@",
                   );
  }

  return RC_WAIT;
}

sub _request_failed {
  my ($response, $fault_code, $fault_string, $result_description) = @_;

  my $response_content =
    ( "<s:Envelope xmlns:s='$soap_namespace'>" .
      "<s:Body><s:Fault>" .
      "<faultcode>s:$fault_code</faultcode>" .
      "<faultstring>$fault_string</faultstring>" .
      "<detail>$result_description</detail>" .
      "</s:Fault></s:Body></s:Envelope>"
    );

  $response->code(200);
  $response->header("Content-Type", "text/xml");
  $response->header("Content-Length", length($response_content));
  $response->content($response_content);
}

package SoapTransaction;

sub TR_RESPONSE () { 0 }
sub TR_SESSION  () { 1 }
sub TR_EVENT    () { 2 }
sub TR_HEADERS  () { 3 }
sub TR_BODY     () { 4 }
sub TR_TYPENAME () { 5 }
sub TR_TYPEURI  () { 6 }

sub start {
  my ($type, $response, $session, $event, $headers, $body) = @_;

  my $self = bless
    [ $response, # TR_RESPONSE
      $session,  # TR_SESSION
      $event,    # TR_EVENT
      $headers,  # TR_HEADERS
      $body,     # TR_BODY
      delete $body->{soap_typename}, # TR_TYPENAME
      delete $body->{soap_typeuri},  # TR_TYPEURI
    ], $type;

  $POE::Kernel::poe_kernel->post($session, $event, $self);
  undef;
}

sub params {
  my $self = shift;
  return $self->[TR_BODY];
}

sub return {
  my ($self, $retval) = @_;

  my $content = '';
  my $em = SOAP::EnvelopeMaker->new(sub { $content .= shift });

  $em->set_body
    ( $self->[TR_TYPEURI],
      $self->[TR_EVENT] . 'Response',
      0,
      { return => $retval }
    );

  my $response = $self->[TR_RESPONSE];

  $response->code(200);
  $response->header("Content-Type", "text/xml");
  $response->header("Content-Length", length($content));
  $response->content($content);
  $response->continue();
}

1;

__END__

=head1 NAME

POE::Component::Server::SOAP - publish POE event handlers via SOAP over HTTP

=head1 SYNOPSIS

  use POE;
  use POE::Component::Server::SOAP;

  POE::Component::Server::SOAP->new( alias => "soapy", port  => 32080 );

  POE::Session->create
    ( inline_states =>
      { _start => \&setup_service,
        _stop  => \&shutdown_service,
        sum_things => \&do_sum,
      }
    );

  $poe_kernel->run;
  exit 0;

  sub setup_service {
    my $kernel = $_[KERNEL];
    $kernel->alias_set("service");
    $kernel->post( soapy => publish => service => "sum_things" );
  }

  sub shutdown_service {
    $_[KERNEL]->post( soapy => rescind => service => "sum_things" );
  }

  sub do_sum {
    my $soap_transaction = $_[ARG0];
    my $params = $soap_transaction->params();
    my $sum = 0;
    while (my ($field, $value) = each(%$params)) {
      $sum += $value;
    }
    $soap_transaction->return("Thanks.  Sum is: $sum");
  }

=head1 DESCRIPTION

POE::Component::Server::SOAP is a bolt-on component that can publish a
event handlers via SOAP over HTTP.

There are four steps to enabling your programs to support SOAP
requests.  First you must load the component.  Then you must
instantiate it.  Each POE::Component::Server::SOAP instance requires
an alias to accept messages with and a port to bind itself to.
Finally, your program should posts a "publish" events to the server
for each event handler it wishes to expose.

  use POE::Component::Server::SOAP;
  POE::Component::Server::SOAP->new( alias => "soapy", port  => 32080 );
  $kernel->post( soapy => publish => session_alias => "event_name" );

Later you can make events private again.

  $kernel->post( soapy => rescind => session_alias => "event_name" );

Finally you must write the SOAP request handler.  SOAP handlers
receive a single parameter, ARG0, which contains a SOAP transaction
object.  The object has two methods: params(), which returns a
reference to a hash of SOAP parameters; and return(), which returns
its parameters to the client as a SOAP response.

  sum_things => sub {
    my $soap_transaction = $_[ARG0];
    my $params = $soap_transaction->params();
    my $sum = 0;
    while (my ($field, $value) = each(%$params)) {
      $sum += $value;
    }
    $soap_transaction->return("Thanks.  Sum is: $sum");
  }

And here is a sample SOAP::Lite client.  It should work with the
server in the SYNOPSIS.

  #!/usr/bin/perl

  use warnings;
  use strict;

  use SOAP::Lite;

  print SOAP::Lite
    -> uri('http://poe_dynodns.net:32080/')
    -> proxy('http://poe.dynodns.net:32080/?session=sum_server')
    -> sum_things(8,6,7,5,3,0,9)
    -> result
    ;
  print "\n";

=head1 BUGS

This project was created over the course of two days, which attests to
the ease of writing new POE components.  However, I did not learn SOAP
in depth, so I am probably not doing things the best they could.
Please pass bug reports and suggestions along to troc+soap@pobox.com.

=head1 SEE ALSO

The examples directory that came with this component.

SOAP::Line
POE::Component::Server::HTTP
POE

=head1 AUTHOR & COPYRIGHTS

POE::Component::Server::SOAP is Copyright 2002 by Rocco Caputo.  All
rights are reserved.  POE::Component::Server::SOAP is free software;
you may redistribute it and/or modify it under the same terms as Perl
itself.

=cut
