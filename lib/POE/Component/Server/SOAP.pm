# Declare our package
package POE::Component::Server::SOAP;

# Standard stuff to catch errors
use strict qw(subs vars refs);				# Make sure we can't mess up
use warnings FATAL => 'all';				# Enable warnings to catch errors
use Carp qw(croak);

use vars qw($VERSION);
$VERSION = '1.02';

use POE;
use POE::Component::Server::SimpleHTTP;
use SOAP::Defs;
use SOAP::EnvelopeMaker;
use SOAP::Parser;
use POE::Component::Server::SOAP::Response;

# Set some constants
BEGIN {
	# Debug fun!
	if ( ! defined &DEBUG ) {
		eval "sub DEBUG () { 0 }";
	}
}

# Create a new instance
sub new {
	# Get the OOP's type
	my $type = shift;

	# Sanity checking
	if ( @_ & 1 ) {
		croak( 'POE::Component::Server::SOAP->new needs even number of options' );
	}

	# The options hash
	my %opt = @_;

	# Our own options
	my ( $ALIAS, $ADDRESS, $PORT, $HEADERS, $HOSTNAME );

	# You could say I should do this: $Stuff = delete $opt{'Stuff'}
	# But, that kind of behavior is not defined, so I would not trust it...

	# Get the session alias
	if ( exists $opt{'ALIAS'} and defined $opt{'ALIAS'} and length( $opt{'ALIAS'} ) ) {
		$ALIAS = $opt{'ALIAS'};
		delete $opt{'ALIAS'};
	} else {
		# Debugging info...
		if ( DEBUG ) {
			warn 'Using default ALIAS = SOAPServer';
		}

		# Set the default
		$ALIAS = 'SOAPServer';
	}

	# Get the PORT
	if ( exists $opt{'PORT'} and defined $opt{'PORT'} and length( $opt{'PORT'} ) ) {
		$PORT = $opt{'PORT'};
		delete $opt{'PORT'};
	} else {
		# Debugging info...
		if ( DEBUG ) {
			warn 'Using default PORT = 80';
		}

		# Set the default
		$PORT = 80;
	}

	# Get the ADDRESS
	if ( exists $opt{'ADDRESS'} and defined $opt{'ADDRESS'} and length( $opt{'ADDRESS'} ) ) {
		$ADDRESS = $opt{'ADDRESS'};
		delete $opt{'ADDRESS'};
	} else {
		croak( 'ADDRESS is required to create a new POE::Component::Server::SOAP instance!' );
	}

	# Get the HEADERS
	if ( exists $opt{'HEADERS'} and defined $opt{'HEADERS'} ) {
		# Make sure it is ref to hash
		if ( ref( $opt{'HEADERS'} ) and ref( $opt{'HEADERS'} ) eq 'HASH' ) {
			$HEADERS = $opt{'HEADERS'};
			delete $opt{'HEADERS'};
		} else {
			croak( 'HEADERS must be a reference to a HASH!' );
		}
	} else {
		# Debugging info...
		if ( DEBUG ) {
			warn 'Using default HEADERS ( SERVER => POE::Component::Server::SOAP/' . $VERSION . ' )';
		}

		# Set the default
		$HEADERS = {
			'SERVER'	=>	'POE::Component::Server::SOAP/' . $VERSION,
		};
	}

	# Get the HOSTNAME
	if ( exists $opt{'HOSTNAME'} and defined $opt{'HOSTNAME'} and length( $opt{'HOSTNAME'} ) ) {
		$HOSTNAME = $opt{'HOSTNAME'};
		delete $opt{'HOSTNAME'};
	} else {
		# Debugging info...
		if ( DEBUG ) {
			warn 'Letting POE::Component::Server::SimpleHTTP create a default HOSTNAME';
		}

		# Set the default
		$HOSTNAME = undef;
	}

	# Anything left over is unrecognized
	if ( keys %opt > 0 ) {
		if ( DEBUG ) {
			croak( 'Unrecognized options were present in POE::Component::Server::SOAP->new -> ' . join( ', ', keys %opt ) );
		}
	}

	# Create the POE Session!
	POE::Session->create(
		'inline_states'	=>	{
			# Generic stuff
			'_start'	=>	\&StartServer,
			'_stop'		=>	sub {},
			'_child'	=>	sub {},

			# Shuts down the server
			'SHUTDOWN'	=>	\&StopServer,

			# Adds/deletes Methods
			'ADDMETHOD'	=>	\&AddMethod,
			'DELMETHOD'	=>	\&DeleteMethod,
			'DELSERVICE'	=>	\&DeleteService,

			# Transaction handlers
			'Got_Request'	=>	\&TransactionStart,
			'ERROR'		=>	\&TransactionError,
			'DONE'		=>	\&TransactionDone,
		},

		# Our own heap
		'heap'		=>	{
			'INTERFACES'	=>	{},
			'ALIAS'		=>	$ALIAS,
			'ADDRESS'	=>	$ADDRESS,
			'PORT'		=>	$PORT,
			'HEADERS'	=>	$HEADERS,
			'HOSTNAME'	=>	$HOSTNAME,
		},
	) or die 'Unable to create a new session!';

	# Return success
	return 1;
}

# Creates the server
sub StartServer {
	# Set the alias
	$_[KERNEL]->alias_set( $_[HEAP]->{'ALIAS'} );

	# Create the webserver!
	POE::Component::Server::SimpleHTTP->new(
		'ALIAS'         =>      $_[HEAP]->{'ALIAS'} . '-BACKEND',
		'ADDRESS'       =>      $_[HEAP]->{'ADDRESS'},
		'PORT'          =>      $_[HEAP]->{'PORT'},
		'HOSTNAME'      =>      $_[HEAP]->{'HOSTNAME'},
		'HEADERS'	=>	$_[HEAP]->{'HEADERS'},
		'HANDLERS'      =>      [
			{
				'DIR'           =>      '.*',
				'SESSION'       =>      $_[HEAP]->{'ALIAS'},
				'EVENT'         =>      'Got_Request',
			},
		],
	) or die 'Unable to create the HTTP Server';
}

# Shuts down the server
sub StopServer {
	# Tell the webserver to die!
	$_[KERNEL]->post( $_[HEAP]->{'ALIAS'} . '-BACKEND', 'SHUTDOWN' );

	# Remove our alias
	$_[KERNEL]->alias_remove( $_[HEAP]->{'ALIAS'} );
}

# Adds a method
sub AddMethod {
	# ARG0: Session alias, ARG1: Session event, ARG2: Service name, ARG3: Method name
	my( $alias, $event, $service, $method );

	# Check for stuff!
	if ( defined $_[ARG0] and length( $_[ARG0] ) ) {
		$alias = $_[ARG0];
	} else {
		# Complain!
		if ( DEBUG ) {
			warn 'Did not get a Session Alias';
		}
		return undef;
	}

	if ( defined $_[ARG1] and length( $_[ARG1] ) ) {
		$event = $_[ARG1];
	} else {
		# Complain!
		if ( DEBUG ) {
			warn 'Did not get a Session Event';
		}
		return undef;
	}

	# If none, defaults to the Session stuff
	if ( defined $_[ARG2] and length( $_[ARG2] ) ) {
		$service = $_[ARG2];
	} else {
		# Debugging stuff
		if ( DEBUG ) {
			warn 'Using Session Alias as Service Name';
		}

		$service = $alias;
	}

	if ( defined $_[ARG3] and length( $_[ARG3] ) ) {
		$method = $_[ARG3];
	} else {
		# Debugging stuff
		if ( DEBUG ) {
			warn 'Using Session Event as Method Name';
		}

		$method = $event;
	}

	# If we are debugging, check if we overwrote another method
	if ( DEBUG ) {
		if ( exists $_[HEAP]->{'INTERFACES'}->{ $service } ) {
			if ( exists $_[HEAP]->{'INTERFACES'}->{ $service }->{ $method } ) {
				warn 'Overwriting old method entry in the registry!';
			}
		}
	}

	# Add it to our INTERFACES
	$_[HEAP]->{'INTERFACES'}->{ $service }->{ $method } = [ $alias, $event ];

	# Return success
	return 1;
}

# Deletes a method
sub DeleteMethod {
	# ARG0: Service name, ARG1: Service method name
	my( $service, $method ) = @_[ ARG0, ARG1 ];

	# Validation
	if ( defined $service and length( $service ) ) {
		# Validation
		if ( defined $method and length( $method ) ) {
			# Validation
			if ( exists $_[HEAP]->{'INTERFACES'}->{ $service }->{ $method } ) {
				# Delete it!
				delete $_[HEAP]->{'INTERFACES'}->{ $service }->{ $method };

				# Check to see if the service now have no methods
				if ( keys( %{ $_[HEAP]->{'INTERFACES'}->{ $service } } ) == 0 ) {
					# Debug stuff
					if ( DEBUG ) {
						warn "Service $service contains no methods, removing it!";
					}

					# Delete it!
					delete $_[HEAP]->{'INTERFACES'}->{ $service };
				}

				# Return success
				return 1;
			} else {
				# Error!
				if ( DEBUG ) {
					warn 'Tried to delete a nonexistant Method in Service -> ' . $service . ' : ' . $method;
				}
				return undef;
			}
		} else {
			# Complain!
			if ( DEBUG ) {
				warn 'Did not get a method to delete in Service -> ' . $service;
			}
			return undef;
		}
	} else {
		# No arguments!
		if ( DEBUG ) {
			warn 'Received no arguments!';
		}
		return undef;
	}
}

# Deletes a service
sub DeleteService {
	# ARG0: Service name
	my( $service ) = $_[ ARG0 ];

	# Validation
	if ( defined $service and length( $service ) ) {
		# Validation
		if ( exists $_[HEAP]->{'INTERFACES'}->{ $service } ) {
			# Delete it!
			delete $_[HEAP]->{'INTERFACES'}->{ $service };

			# Return success!
			return 1;
		} else {
			# Error!
			if ( DEBUG ) {
				warn 'Tried to delete a Service that does not exist! -> ' . $service;
			}
			return undef;
		}
	} else {
		# No arguments!
		if ( DEBUG ) {
			warn 'Received no arguments!';
		}
		return undef;
	}
}

# Got a request, handle it!
sub TransactionStart {
	# ARG0 = HTTP::Request, ARG1 = HTTP::Response, ARG2 = dir that matched
	my ( $request, $response ) = @_[ ARG0, ARG1 ];

	# Check for error in parsing of request
	if ( ! defined $request ) {
		# Create a new error and send it off!
		$_[KERNEL]->yield( 'ERROR',
			$response,
			$soap_fc_client,
			'Bad Request',
			'Unable to parse HTTP query',
		);
		return;
	}

	# Get some stuff
	my $query_string = $request->uri->query();
	if ( ! defined $query_string or $query_string !~ /\bsession=(.+ $ )/x ) {
		# Create a new error and send it off!
		$_[KERNEL]->yield( 'ERROR',
			$response,
			$soap_fc_client,
			'Bad Request',
			'Unable to parse the URI for the service',
		);
		return;
	}

	# Get the service
	my $service = $1;

	# Check to see if this service exists
	if ( ! exists $_[HEAP]->{'INTERFACES'}->{ $service } ) {
		# Create a new error and send it off!
		$_[KERNEL]->yield( 'ERROR',
			$response,
			$soap_fc_client,
			'Bad Request',
			"Unknown service: $service",
		);
		return;
	}

	# We only handle text/xml content
	if ( $request->header('Content-Type') !~ /^text\/xml(;.*)?$/ ) {
		# Create a new error and send it off!
		$_[KERNEL]->yield( 'ERROR',
			$response,
			$soap_fc_client,
			'Bad Request',
			'Content-Type must be text/xml',
		);
		return;
	}

	# We need the method name
	my $soap_method_name = $request->header('SOAPAction');
	if ( ! defined $soap_method_name or ! length( $soap_method_name ) ) {
		# Create a new error and send it off!
		$_[KERNEL]->yield( 'ERROR',
			$response,
			$soap_fc_client,
			'Bad Request',
			'SOAPAction is required',
		);
		return;
	}

	# Get the method name
	if ( $soap_method_name !~ /^([\"\']?)(\S+)\#(\S+)\1$/ ) {
		# Create a new error and send it off!
		$_[KERNEL]->yield( 'ERROR',
			$response,
			$soap_fc_client,
			'Bad Request',
			"Unrecognized SOAPAction header: $soap_method_name",
		);
		return;
	}

	# Get the method
	my $method = $3;

	# Check to see if this method exists
	if ( ! exists $_[HEAP]->{'INTERFACES'}->{ $service }->{ $method } ) {
		# Create a new error and send it off!
		$_[KERNEL]->yield( 'ERROR',
			$response,
			$soap_fc_client,
			'Bad Request',
			"Unknown method: $method",
		);
		return;
	}

	# Actually parse the SOAP query!
	my ( $headers, $body );
	eval {
		my $soap_parser = SOAP::Parser->new();
		$soap_parser->parsestring( $request->content() );
		$headers = $soap_parser->get_headers();
		$body = $soap_parser->get_body();
	};

	# Check for errors
	if ( $@ ) {
		# Create a new error and send it off!
		$_[KERNEL]->yield( 'ERROR',
			$response,
			$soap_fc_server,
			'Application Faulted',
			"Failed while unmarshaling the request: $@",
		);
		return;
	}

	# Hax0r the Response to include our stuff!
	$response->{'SOAPMETHOD'} = $method;
	$response->{'SOAPBODY'} = $body;
	$response->{'SOAPHEADERS'} = $headers;
	$response->{'SOAPSERVICE'} = $service;
	$response->{'SOAPREQUEST'} = $request;

	# Do we have a body?
	if ( defined $body and ref( $body ) and ref( $body ) eq 'HASH' ) {
		# Move them over to the appropriate places
		if ( exists $body->{'soap_typeuri'} ) {
			$response->{'SOAPTYPEURI'} = delete $body->{'soap_typeuri'};
		} else {
			$response->{'SOAPTYPEURI'} = undef;
		}

		if ( exists $body->{'soap_typename'} ) {
			$response->{'SOAPTYPENAME'} = delete $body->{'soap_typename'};
		} else {
			$response->{'SOAPTYPENAME'} = undef;
		}
	} else {
		# Make sure SOAP::Response won't crash on undefined hash keys
		$response->{'SOAPTYPEURI'} = undef;
		$response->{'SOAPTYPENAME'} = undef;
	}

	# ReBless it ;)
	bless( $response, 'POE::Component::Server::SOAP::Response' );

	# Send it off to the handler!
	$_[KERNEL]->post( $_[HEAP]->{'INTERFACES'}->{ $service }->{ $method }->[0],
		$_[HEAP]->{'INTERFACES'}->{ $service }->{ $method }->[1],
		$response,
	);

	# Debugging stuff
	if ( DEBUG ) {
		warn "Finished processing Service $service -> Method $method";
	}

	# All done!
	return 1;
}

# Creates the error and sends it off
sub TransactionError {
	# ARG0 = SOAP::Response, ARG1 = SOAP faultcode, ARG2 = SOAP faultstring, ARG3 = SOAP Fault Detail, ARG4 = SOAP Fault Actor
	my ( $response, $fault_code, $fault_string, $fault_detail, $fault_actor ) = @_[ ARG0 .. ARG4 ];

	# Make sure we have a SOAP::Response object here :)
	if ( ! defined $response ) {
		# Debug stuff
		if ( DEBUG ) {
			warn 'Received ERROR event but no arguments!';
		}
		return undef;
	}

	# Fault Code must be defined
	if ( ! defined $fault_code or ! length( $fault_code ) ) {
		# Debug stuff
		if ( DEBUG ) {
			warn 'Setting default Fault Code';
		}

		# Set the default
		$fault_code = 'Server';
	}

	# FaultString is a short description of the error
	if ( ! defined $fault_string or ! length( $fault_string ) ) {
		# Debug stuff
		if ( DEBUG ) {
			warn 'Setting default Fault String';
		}

		# Set the default
		$fault_string = 'Application Faulted';
	}

	# Prefabricate the SOAP stuff
	my $response_content = "<?xml version=\"1.0\"?><s:Envelope xmlns:s='$soap_namespace'><s:Body><s:Fault><faultcode>$fault_code</faultcode><faultstring>$fault_string</faultstring>";

	# Add the detail if applicable
	if ( defined $fault_detail and length( $fault_detail ) ) {
		$response_content .= "<detail>$fault_detail</detail>";
	}

	# Add the actor if applicable
	if ( defined $fault_actor and length( $fault_actor ) ) {
		$response_content .= "<faultactor>$fault_actor</faultactor>";
	}

	# Add the rest...
	$response_content .= '</s:Fault></s:Body></s:Envelope>';

	# Setup the response
	$response->code( 500 );
	$response->header( 'Content-Type', 'text/xml' );
	$response->content( $response_content );

	# Send it off to the backend!
	$_[KERNEL]->post( $_[HEAP]->{'ALIAS'} . '-BACKEND', 'DONE', $response );

	# Debugging stuff
	if ( DEBUG ) {
		warn 'Finished processing ERROR response';
	}

	# All done!
	return 1;
}

# All done with a transaction!
sub TransactionDone {
	# ARG0 = SOAP::Response object
	my $response = $_[ARG0];

	# Create the content
	my $content = '';
	my $em = SOAP::EnvelopeMaker->new( sub { $content .= shift } );

	# Setup the EnvelopeMaker
	$em->set_body(
		$response->soaptypeuri(),
		$response->soapmethod() . 'Response',
		0,
		{ return => $response->content() },
	);

	# Set up the response!
	$response->code( 200 );
	$response->header( 'Content-Type', 'text/xml' );
	$response->content( $content );

	# Send it off!
	$_[KERNEL]->post( $_[HEAP]->{'ALIAS'} . '-BACKEND', 'DONE', $response );

	# Debug stuff
	if ( DEBUG ) {
		warn "Finished processing Method " . $response->soapmethod();
	}

	# All done!
	return 1;
}

1;

__END__

=head1 NAME

POE::Component::Server::SOAP - publish POE event handlers via SOAP over HTTP

=head1 SYNOPSIS

	use POE;
	use POE::Component::Server::SOAP;

	POE::Component::Server::SOAP->new(
		'ALIAS'		=>	'MySOAP',
		'ADDRESS'	=>	'localhost',
		'PORT'		=>	32080,
		'HOSTNAME'	=>	'MyHost.com',
	);

	POE::Session->create(
		'inline_states'	=>	{
			'_start'	=>	\&setup_service,
			'_stop'		=>	\&shutdown_service,
			'Sum_Things'	=>	\&do_sum,
		},
	);

	$poe_kernel->run;
	exit 0;

	sub setup_service {
		my $kernel = $_[KERNEL];
		$kernel->alias_set( 'MyServer' );
		$kernel->post( 'MySOAP', 'ADDMETHOD', 'MyServer', 'Sum_Things' );
	}

	sub shutdown_service {
		$_[KERNEL]->post( 'MySOAP', 'DELMETHOD', 'MyServer', 'Sum_Things' );
	}

	sub do_sum {
		my $response = $_[ARG0];
		my $params = $response->soapbody;
		my $sum = 0;
		while (my ($field, $value) = each(%$params)) {
			$sum += $value;
		}

		# Fake an error
		if ( $sum < 100 ) {
			$_[KERNEL]->post( 'MySOAP', 'ERROR', $response, 'Add:Error', 'The sum must be above 100' );
		} else {
			$_[KERNEL]->post( 'MySOAP', 'DONE', $response, "Thanks.  Sum is: $sum" );
		}
	}

=head1 CHANGES

=head2 1.02

	POD Formatting ( I'm still not an expert )
	I forgot to add the test to the MANIFEST, so the distribution had no tests... *gah*

=head2 1.01

	Took over ownership of this module from Rocco Caputo
	Broke just about everything :)

=head2 0.03

	Old version from Rocco Caputo

=head1 ABSTRACT

	An easy to use SOAP/1.1 daemon for POE-enabled programs

=head1 DESCRIPTION

This module makes serving up SOAP/1.1 requests a breeze in POE.

The hardest thing to understand in this module is the SOAP Body. That's it!

The standard way to use this module is to do this:

	use POE;
	use POE::Component::Server::SOAP;

	POE::Component::Server::SOAP->new( ... );

	POE::Session->create( ... );

	POE::Kernel->run();

POE::Component::Server::SOAP is a bolt-on component that can publish event handlers via SOAP over HTTP.
Currently, this module only supports SOAP/1.1 requests, work will be done in the future to support SOAP/1.2 requests.
The HTTP server is done via POE::Component::Server::SimpleHTTP.

=head2 Starting Server::SOAP

To start Server::SOAP, just call it's new method:

	POE::Component::Server::SOAP->new(
		'ALIAS'		=>	'MySOAP',
		'ADDRESS'	=>	'192.168.1.1',
		'PORT'		=>	11111,
		'HOSTNAME'	=>	'MySite.com',
		'HEADERS'	=>	{},
	);

This method will die on error or return success.

This constructor accepts only 5 options.

=over 4

=item C<ALIAS>

This will set the alias Server::SOAP uses in the POE Kernel.
This will default to "SOAPServer"

=item C<ADDRESS>

This value will be passed to POE::Component::Server::SimpleHTTP to bind to.

=item C<PORT>

This value will be passed to POE::Component::Server::SimpleHTTP to bind to.

=item C<HOSTNAME>

This value is for the HTTP::Request's URI to point to.
If this is not supplied, POE::Component::Server::SimpleHTTP will use Sys::Hostname to find it.

=item C<HEADERS>

This should be a hashref, that will become the default headers on all HTTP::Response objects.
You can override this in individual requests by setting it via $request->header( ... )

The default header is:
	SERVER => 'POE::Component::Server::SOAP/' . $VERSION

For more information, consult the L<HTTP::Headers> module.

=back

=head2 Events

There are only a few ways to communicate with Server::SOAP.

=over 4

=item C<DONE>

	This event accepts only one argument: the SOAP::Response object we sent to the handler.

	Calling this event implies that this particular request is done, and will proceed to close the socket.

	The content in $response->content() will be automatically serialized via SOAP::EnvelopeMaker

	NOTE: This method automatically sets some parameters:
		- HTTP Status = 200
		- HTTP Header value of 'Content-Type' = 'text/xml'

	To get greater throughput and response time, do not post() to the DONE event, call() it!
	However, this will force your program to block while servicing SOAP requests...

=item C<ERROR>

	This event accepts five arguments:
		- the HTTP::Response object we sent to the handler
		- SOAP Fault Code	( not required -> defaults to 'Server' )
		- SOAP Fault String	( not required -> defaults to 'Application Faulted' )
		- SOAP Fault Detail	( not required )
		- SOAP Fault Actor	( not required )

	Again, calling this event implies that this particular request is done, and will proceed to close the socket.

	NOTE: This method automatically sets some parameters:
		- HTTP Status = 500
		- HTTP Header value of 'Content-Type' = 'text/xml'
		- HTTP Content = SOAP Envelope of the fault ( overwriting anything that was there )

=item C<ADDMETHOD>

	This event accepts four arguments:
		- The intended session alias
		- The intended session event
		- The public service name	( not required -> defaults to session alias )
		- The public method name	( not required -> defaults to session event )

	Calling this event will add the method to the registry.

	NOTE: This will overwrite the old definition of a method if it exists!

=item C<DELMETHOD>

	This event accepts two arguments:
		- The service name
		- The method name

	Calling this event will remove the method from the registry.

	NOTE: if the service now contains no methods, it will also be removed.

=item C<DELSERVICE>

	This event accepts one argument:
		- The service name

	Calling this event will remove the entire service from the registry.

=item C<SHUTDOWN>

	Calling this event makes Server::SOAP shut down by closing it's TCP socket.

=back

=head2 Processing Requests

if you're new to the world of SOAP, reading the documentation by the excellent author of SOAP::Lite is recommended!
It also would help to read some stuff at http://www.soapware.org/ -> They have some excellent links :)

Now, once you have set up the services/methods, what do you expect from Server::SOAP?
Every request is pretty straightforward, you just get a Server::SOAP::Response object in ARG0.

	The SOAP::Response object contains a wealth of information about the specified request:
		- There is the SimpleHTTP::Connection object, which gives you connection information
		- There is the various SOAP accessors provided via SOAP::Response
		- There is the HTTP::Request object

	Example information you can get:
		$response->connection->remote_ip()	# IP of the client
		$response->soaprequest->uri()		# Original URI
		$response->soapmethod()			# The SOAP method that was called
		$response->soapbody()			# The arguments to the method

Probably the most important part of SOAP::Response is the body of the message, which contains the arguments to the method call.
The data in the body is a hash, for more information look at SOAP::Parser.

I cannot guarantee what will be in the body, it is all up to the SOAP serializer/deserializer. Server::SOAP will do one thing, that is
to remove the 'soap_typeuri' and 'soap_typename' if the body is a hash and those keys exist. ( They will still be accessible via the
methods in the Server::SOAP::Response object ) I can provide some examples:

	Calling a SOAP method with an array:
		print SOAP::Lite
			-> uri('http://localhost:32080/')
			-> proxy('http://localhost:32080/?session=MyServer')
			-> Sum_Things(8,6,7,5,3,0,9,183)
			-> result

	The body will look like this:
		$VAR1 = {
			'c-gensym17' => '183',
			'c-gensym5' => '6',
			'c-gensym13' => '0',
			'c-gensym11' => '3',
			'c-gensym15' => '9',
			'c-gensym9' => '5',
			'c-gensym3' => '8',
			'c-gensym7' => '7'
		};

	Calling a SOAP method with a hash:
		print SOAP::Lite
			-> uri('http://localhost:32080/')
			-> proxy('http://localhost:32080/?session=MyServer')
			-> Sum_Things(	{
				'FOO'	=>	'bax',
				'Hello'	=>	'World!',
			}	)
			-> result

	The body will look like this:
		$VAR1 = {
			'c-gensym21' => {
				'Hello' => 'World!',
				'FOO' => 'bax',
				'soap_typename' => 'SOAPStruct',
				'soap_typeuri' => 'http://xml.apache.org/xml-soap'
			}
		};

	Calling a SOAP method using SOAP::Data methods:
		print SOAP::Lite
			-> uri('http://localhost:32080/')
			-> proxy('http://localhost:32080/?session=MyServer')
			-> Sum_Things(
				SOAP::Data->name( 'Foo', 'harz' ),
				SOAP::Data->name( 'Param', 'value' ),
			)-> result

	The body will look like this:
		$VAR1 = {
			'Param' => 'value',
			'Foo' => 'harz'
		};

Simply experiment using Data::Dumper and you'll quickly get the hang of it!

When you're done with the SOAP request, stuff whatever output you have into the content of the response object.

	$response->content( 'The result is ... ' );

The only thing left to do is send it off to the DONE event :)

	$_[KERNEL]->post( 'MySOAP', 'DONE', $response );

=head2 Server::SOAP Notes

This module is very picky about capitalization!

All of the options are uppercase, to avoid confusion.

You can enable debugging mode by doing this:

	sub POE::Component::Server::SOAP::DEBUG () { 1 }
	use POE::Component::Server::SOAP;

Yes, I broke a lot of things in this release ( 1.01 ), but Rocco agreed that it's best to break things
as early as possible, so that development can move on instead of being stuck on legacy issues.

=head1 SEE ALSO

The examples directory that came with this component.

L<POE>

L<HTTP::Response>

L<POE::Component::Server::SOAP::Response>

L<SOAP::Lite>

L<SOAP::Parser>

L<SOAP>

=head1 AUTHOR

Apocalypse E<lt>apocal@cpan.orgE<gt>

I took over this module from Rocco Caputo. Here is his stuff:

	POE::Component::Server::SOAP is Copyright 2002 by Rocco Caputo.  All
	rights are reserved.  POE::Component::Server::SOAP is free software;
	you may redistribute it and/or modify it under the same terms as Perl
	itself.

	Rocco may be contacted by e-mail via rcaputo@cpan.org.

=head1 COPYRIGHT AND LICENSE

Copyright 2004 by Apocalypse

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
