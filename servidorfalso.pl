#!/usr/bin/perl

use strict;
use warnings;
use IO::Socket::INET;
use IPC::SysV;

$SIG{INT}=\&trap;

my $iface = IO::Socket::INET->new(
   LocalAddr => '127.0.0.1',
   LocalPort => 7001,
   Listen   => SOMAXCONN,
   Reuse    => 1,
   Proto    => 'tcp') or die "Erro IO::Socket new()\n";

my $data;

my $conn = $iface->accept();

while(1) {
   $data = <$conn>;
   #if($data){
      print $data,"\n";
   #}
}


$iface->close;

sub trap {
   $iface->close;
   die "ByeBye!\n";   
}


