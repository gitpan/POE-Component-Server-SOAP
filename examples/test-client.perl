#!/usr/bin/perl

use warnings;
use strict;

use SOAP::Lite;

print SOAP::Lite
  -> uri('http://poe_dynodns.net:32080/')
  -> proxy('http://poe.dynodns.net:32080/?session=time_server')
  -> get_localtime("")
  -> result
  ;
print "\n";
