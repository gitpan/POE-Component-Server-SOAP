#!/usr/bin/perl

use warnings;
use strict;

use SOAP::Lite;

print SOAP::Lite
  -> uri('http://poe_dynodns.net:32080/')
  -> proxy('http://poe.dynodns.net:32080/?session=time_server')
  -> sum_things(8,6,7,5,3,0,9)
  -> result
  ;
print "\n";
