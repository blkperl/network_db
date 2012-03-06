#!/usr/local/bin/perl

  use strict;
  use DBI;
  use Net::SNMP qw(:snmp);

  push @INC, $ENV{"HOME"};
  require ".network_db.pl";  # Log into database, defines  $dbh

our $source=$0;

my $iportsql="INSERT INTO switchport
	(switch, switchport, longport, speed, ifindex)
	 VALUES (?, ?, ?, ?, ?);";

my $uportsql="UPDATE switchport SET type=?
	 WHERE switch=? and ifindex=?;";

my $iport = $network_db::dbh->prepare($iportsql) 
        or die "Couldn't prepare statement: " . $network_db::dbh->errstr;
my $uport = $network_db::dbh->prepare($uportsql) 
        or die "Couldn't prepare statement: " . $network_db::dbh->errstr;


# IF-MIB::ifName.10101 = STRING: Gi1/0/1
# IF-MIB::ifDescr.10101 = STRING: GigabitEthernet1/0/1

# SNMPv2-SMI::mib-2.47.1.1.1.1.2.1008 = STRING: "GigabitEthernet1/0/1"
# SNMPv2-SMI::mib-2.47.1.1.1.1.14.1008 = STRING: "10101"
# SNMPv2-SMI::mib-2.47.1.3.2.1.2.1008.0 = OID: IF-MIB::ifIndex.10101

#IF-MIB::ifAlias.10122 = STRING: bunny [86-06 MR10-4]
# SNMPv2-SMI::mib-2.47.1.1.1.1.2.1008 = STRING: "GigabitEthernet1/0/1"
# SNMPv2-SMI::mib-2.47.1.1.1.1.2.2059 = STRING: "1000BaseSX SFP"



our $ifMIB    = "1.3.6.1.2.1";
our $ifTable  = "1.3.6.1.2.1.2.2.1";
our $ifIndex  = "1.3.6.1.2.1.2.2.1.1";
our $ifDescr  = "1.3.6.1.2.1.2.2.1.2";
our $ifXTable = "1.3.6.1.2.1.31.1.1";
our $ifName   = "1.3.6.1.2.1.31.1.1.1.1";
our $ifAlias  = "1.3.6.1.2.1.31.1.1.1.18";
our $entPhysicalTable = "1.3.6.1.2.1.47.1.1.1.1";
our $entPhysicalDescr = "1.3.6.1.2.1.47.1.1.1.1.2";
our $entPhysicalAlias = "1.3.6.1.2.1.47.1.1.1.1.14";
our $entPhysicalModelName = "1.3.6.1.2.1.47.1.1.1.1.13";

our $entLogicalTable  = "1.3.6.1.2.1.47.1.2.1.1";
our $entLogicalType   = "1.3.6.1.2.1.47.1.2.1.1.3";

while (my $switch = shift) {

(my $session, my $error) = Net::SNMP->session(
                           -hostname      => $switch . ".seas.pdx.edu",
#                           [-port          => $port,]
#                           [-localaddr     => $localaddr,]
#                           [-localport     => $localport,]
#                           [-nonblocking   => $boolean,]
                           -version       => 2,
#                           [-domain        => $domain,]
#                           [-timeout       => $seconds,]
#                           [-retries       => $count,]
#                           [-maxmsgsize    => $octets,]
#                           [-translate     => $translate,]
#                           [-debug         => $bitmask,]
                           -community     => $network_db::community,   # v1/v2c
#                           [-username      => $username,]    # v3
#                           [-authkey       => $authkey,]     # v3
#                           [-authpassword  => $authpasswd,]  # v3
#                           [-authprotocol  => $authproto,]   # v3
#                           [-privkey       => $privkey,]     # v3
#                           [-privpassword  => $privpasswd,]  # v3
#                           [-privprotocol  => $privproto,]   # v3
                        );

  my $table = $session->get_table( -baseoid          => $ifTable);
  my $Xtable = $session->get_table( -baseoid          => $ifXTable);

  for my $oid (sort keys %$table) {
         $_=$oid;
         if ((my $index)= /$ifIndex\.(.+)/)  {
             my $switchport= $Xtable -> {$ifName  . "." . $index};
             my $longport  = $table  -> {$ifDescr . "." . $index};
             my $speed=undef; # first guess
             if ($switchport =~ /^Te/) {$speed = 10000};
             if ($switchport =~ /^Gi/) {$speed = 1000};
             if ($switchport =~ /^Fa/) {$speed = 100};
#             printf "%7s %10s %25s %s\n", $index,
#                     $Xtable -> {$ifName  . "." . $index},
#                     $longport, $speed;
                 

             #printf "%s = %s\n", $oid, $table{$oid};
             $iport->execute($switch, $switchport, $longport, $speed, $index);
         }
  }

#  my $Ptable = $session->get_table( -baseoid          => $entPhysicalTable);
#  my $Ltable = $session->get_table( -baseoid          => $entLogicalTable);
#
#  for my $oid (sort keys %$Ptable) {
#         $_=$oid;
#         if ((my $index)= /$entPhysicalAlias\.(.+)/)  {
#             my $ifi  = $Ptable -> {$entPhysicalAlias . "." . $index};
##             my $type = $Ptable -> {$entPhysicalModelName   . "." . $index};
#             my $type = $Ptable -> {$entPhysicalDescr   . "." . $index};
#             printf "%7s %10s %s\n", $index,
#                     $ifi, $type;
#                 
#
#             #printf "%s = %s\n", $oid, $table{$oid};
#             #$uport->exec ($type, $switch, $ifi);
#         }
#  }
#
}
