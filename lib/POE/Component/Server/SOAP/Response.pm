# Declare our package
package POE::Component::Server::SOAP::Response;

# Standard stuff to catch errors
use strict qw(subs vars refs);				# Make sure we can't mess up
use warnings FATAL => 'all';				# Enable warnings to catch errors

# Initialize our version
our $VERSION = '1.02';

# Set our stuff to SimpleHTTP::Response
use base qw( POE::Component::Server::SimpleHTTP::Response );

# Accessor for SOAP Service name
sub soapservice {
	return shift->{'SOAPSERVICE'};
}

# Accessor for SOAP Method name
sub soapmethod {
	return shift->{'SOAPMETHOD'};
}

# Accessor for SOAP Headers
sub soapheaders {
	return shift->{'SOAPHEADERS'};
}

# Accessor for SOAP Body
sub soapbody {
	return shift->{'SOAPBODY'};
}

# Accessor for SOAP URI
sub soapuri {
	return shift->{'SOAPURI'};
}

# Accessor for the original HTTP::Request object
sub soaprequest {
	return shift->{'SOAPREQUEST'};
}

# End of module
1;

__END__
=head1 NAME

POE::Component::Server::SOAP::Response - Emulates a SimpleHTTP::Response object, used to store SOAP data

=head1 SYNOPSIS

	use POE::Component::Server::SOAP;

	# Get the response object from SOAP
	my $response = $_[ARG0];

	print $response->soapmethod;

=head1 CHANGES

=head2 1.02

	Renamed the accessor "soaptypeuri" to "soapuri"
	Removed the unnecessary "soaptypename" accessor
	Fixed POD wording due to switch between SOAP::Parser and SOAP::Lite

=head2 1.01

	Initial Revision

=head1 DESCRIPTION

	This module is used as a drop-in replacement, because we need to store some SOAP data for the response.

=head2 METHODS

	# Get the response object from SOAP
	my $response = $_[ARG0];

	$response->soaprequest()	# Returns the original HTTP::Request object from SimpleHTTP
	$response->soapservice()	# Returns the service that triggered this SOAP instance
	$response->soapmethod()		# Returns the method that triggered this SOAP instance
	$response->soapuri()		# Returns the original URI of the request without the method
	$response->soapheaders()	# Returns an arrayref of SOAP::Header objects ( undef if none )
	$response->soapbody()		# Returns the body as a hashref ( undef if no arguments )

=head2 EXPORT

Nothing.

=head1 SEE ALSO

	L<POE::Component::Server::SimpleHTTP>

	L<POE::Component::Server::SimpleHTTP::Connection>

	L<POE::Component::Server::SOAP>

	L<SOAP::Lite>

=head1 AUTHOR

Apocalypse E<lt>apocal@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2004 by Apocalypse

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut