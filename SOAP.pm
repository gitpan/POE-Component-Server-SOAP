# $Id: SOAP.pm,v 1.1 2002/09/06 21:54:25 rcaputo Exp $
# License and documentation are after __END__.

package POE::Component::Server::SOAP;

use warnings;
use strict;
use Carp qw(croak);

use vars qw($VERSION);
$VERSION = '0.01';

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
sub TR_PARAMS   () { 5 }

sub start {
  my ($type, $response, $session, $event, $headers, $body) = @_;

  my @params;
  foreach my $key (sort keys %$body) {
    next if $key eq "soap_typeuri";
    next if $key eq "soap_typename";
    push @params, $body->{$key};
  }

  my $self = bless
    [ $response,  # TR_RESPONSE
      $session,   # TR_SESSION
      $event,     # TR_EVENT
      $headers,   # TR_HEADERS
      $body,      # TR_BODY
      \@params,   # TR_PARAMS
    ], $type;

  $POE::Kernel::poe_kernel->post($session, $event, $self);
  undef;
}

sub params {
  my $self = shift;
  return @{$self->[TR_PARAMS]};
}

sub return {
  my ($self, $retval) = @_;

  my $content = '';
  my $em = SOAP::EnvelopeMaker->new(sub { $content .= shift });

  $em->set_body
    ( $self->[TR_BODY]->{soap_typeuri},
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
