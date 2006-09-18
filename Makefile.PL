use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
	'NAME'		=>	'POE::Component::Server::SOAP',
	'VERSION_FROM'	=>	'lib/POE/Component/Server/SOAP.pm', # finds $VERSION
	'PREREQ_PM'	=> {
		'POE'					=>	'0.29',
		'POE::Component::Server::SimpleHTTP'	=>	'1.10',
		'SOAP::Lite'				=>	'0.55',

	},
	(	$] >= 5.005 ?		# Add new keywords
		(
			'ABSTRACT_FROM'	=> 'lib/POE/Component/Server/SOAP.pm', # retrieve abstract from module
			'AUTHOR'	=> 'Apocalypse <APOCAL@cpan.org>',
		) : ()
	),

	# Thanks POE!
	'dist'		=> {
		'PREOP'		=> (
			"echo 'license: perl' >> ./META.yml;" .
			'/bin/cp -f ./META.yml ./$(DISTNAME)-$(VERSION)/META.yml &2>/dev/null'
		),
	},
);
