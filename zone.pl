#!/usr/bin/perl -T
  use strict;
  use DBI;
  $ENV{PATH}="";

my $username="davburns";
my $password="YouThinkIdTellYou";

our $zoneprefix="/u/davburns/oper/database/dnsdb/";
our $nodeortab;
our %zoneres, our %dupezone;

$zoneres{"cee.pdx.edu"}="cee?.pdx.edu";
$zoneres{"mme.pdx.edu"}="mm?e.pdx.edu";
$zoneres{"ece.pdx.edu"}="ec?e.pdx.edu";
$zoneres{"cecs.pdx.edu"}="(cecs|eas).pdx.edu";

$dupezone{"cee.pdx.edu"}="ce.pdx.edu";
$dupezone{"mme.pdx.edu"}="me.pdx.edu";
$dupezone{"ece.pdx.edu"}="ee.pdx.edu";
$dupezone{"cecs.pdx.edu"}="eas.pdx.edu";

our $dbh = DBI->connect("DBI:Pg:dbname=network_db host=walt.ee.pdx.edu password=$password")
        or die "Couldn't connect to database: " . DBI->errstr;

# Prepare our queries
our $qh_zones = $dbh->prepare("SELECT zone, serial FROM dns.soa WHERE touched;");

our $qh_touch = $dbh->prepare("UPDATE dns.soa SET touched=false, serial=? "
                           . "WHERE zone=?;");

our $qh_soa   = $dbh->prepare("SELECT * FROM dns.soa WHERE zone=?;");

our $qh_ptr   = $dbh->prepare("SELECT * FROM dns.ipname "
                           . "WHERE ip_addr << ? AND ptr ORDER BY ip_addr;");

our $qh_nodes = $dbh->prepare("SELECT name FROM dns.ipname "
                           . "WHERE name ~* ? "
                           . "UNION SELECT name FROM dns.xzone "
                           . "WHERE name ~* ?;");

our $qh_ipname= $dbh->prepare("SELECT * FROM dns.ipname "
			   .  " WHERE name = ? AND a;");

our $qh_xzone = $dbh->prepare("SELECT * FROM dns.xzone where name = ?;");

our $qh_usr = $dbh->prepare("SELECT * FROM hostname JOIN hostuser "
                          . " USING (hostid) WHERE name = ?;");

our $qh_loc = $dbh->prepare("SELECT * FROM hostname JOIN hostlocation "
                          . " USING (hostid) WHERE name = ?;");

our $qh_hinfo = $dbh->prepare("SELECT hardware, os FROM hostname "
			. " FULL JOIN hostinventory USING (hostid) "
			. " FULL JOIN hostsupport USING (hostid) "
			. " WHERE name = ?;");

sub ballance{
   ($_)=@_;
   if (/^[^"]*("[^"]*"[^"]*)*$/ && /^[^()]*(\([^()]*\)[^()]*)*[^()]*$/) {
	return $_;
   } else {
	print STDERR ("Unballanced: $_\n");
	return undef;
   }
}

sub xzone {
  (my $name) = @_;
  # "SELECT * FROM dns.xzone where name = $name;"
  $qh_xzone->execute($name);
  while ( my $rrs=$qh_xzone->fetchrow_hashref ) {
    #TODO  Add some sanity checking here
    ballance($rrs->{"type"}) || die $name; 
    ballance($rrs->{"data"}) || die $name;
    printf ZONE "%s\tIN\t%s\t%s\n", $nodeortab, $rrs->{"type"}, $rrs->{"data"};
    $nodeortab="\t";
  }
}


(my $sec, my $min, my $hour, my $mday, my $mon, my $year, my $wday, 
	my $yday, my $isdst)=localtime(time);
my $dateserial= sprintf "%4d%02d%02d00",  $year+1900,$mon+1,$mday;

my $hostname="walt.ee.pdx.edu.";

# "SELECT zone, serial FROM dns.soa WHERE touched;"
$qh_zones->execute or die  $qh_zones->errstr;

while (my $zoneref=$qh_zones->fetchrow_hashref) {
  # $zoneref->{"zone"}, $zoneref->{"serial"};
  my $zone=$zoneref->{"zone"};
  my $zonere = $zoneres{$zone} ? $zoneres{$zone} : $zone;

  #SQUIDBRAIN!
  my $serial=($dateserial>$zoneref->{"serial"}) 
	? $dateserial : $zoneref->{"serial"}+1;

  # "UPDATE dns.soa SET touched=false, serial++"
  $qh_touch->execute($serial, $zone) or die $qh_touch->errstr;

  # Re-select the SOA to include new serial and win any races
  # "SELECT * FROM dns.soa WHERE zone=$zone;"
  $qh_soa->execute($zone) or die  $qh_soa->errstr;
  my $soa = $qh_soa->fetchrow_hashref;
  # zone zttl hostmaster mail serial refresh retry expire nttl touched

  # open zone file
  open ZONE, "> " . $zoneprefix . $zone . ".tmp";

  printf ZONE "\$TTL %d\n", $soa->{"zttl"};
  printf ZONE "@\t\tIN\tSOA\t%s %s (\n\t\t\t\t%d %d %d %d %d)\n",
	$soa->{"hostmaster"}, $soa->{"mail"}, $soa->{"serial"},
	$soa->{"refresh"}, $soa->{"retry"}, $soa->{"expire"}, $soa->{"nttl"};

  $nodeortab="\t";
  xzone($zone);
  


  if ($zone =~ /arpa\.?$/) {
    # Reverse pointers
    #  Get $subnet from $zone
    my $subnet;
    my $bits;

    if ($zone =~ /in-addr/ ) {
      # IPv4
      $zone =~ /^(\d+\.)?(\d+\.)?(\d+\.)?in-addr.arpa\.?$/;
      $subnet= ($3) ? "$3$2$1". "0/24" : undef;

    } else {
      # IPv6 !
      my @zone=split /\./, $zone;
      pop @zone;  # arpa
      pop @zone;  # ip6
      while ( @zone ) {
	my $x = pop @zone;
	$bits += 4;
	$subnet .= $x;
	$subnet .= ":" if (0==$bits%16) ;
      }
      $subnet .= ( (0==$bits%16) ? ":/" : "::/") . $bits;
    }

    
    #  "SELECT * FROM dns.ipname where ip_addr << $subnet AND ptr ORDER BY ip_addr;"
    $qh_ptr->execute ($subnet) or die qh_ptr->errstr;

    while ( my $noderef=$qh_ptr->fetchrow_hashref ) {
    #name, ip_addr, ptr, a, source, sourcedate
      #   make $node from $ip_addr and $zone
      my $node;
      if ($zone =~ /in-addr/ ) {
	# IPv4
	$noderef->{ip_addr} =~ /(\d+\.\d+\.\d+\.)(\d+)/;
	$node=$2;
      } else {
	# IPv6
	my @ip_addr= split //, $noderef->{ip_addr};
	my $rbits;
        my $colon;
	while ($rbits < $bits) {
	  $_=pop @ip_addr;
	  if (/:/) {
	    while (0!=$rbits%16) {
		$node .= "0";
		$rbits+=4;
		$node .= "." if ($rbits < $bits);
	    }
	    if ($colon) {
		# Double colon! Fill it up to rbits
		while ($rbits < $bits) {
		    $node .= "0";
		    $rbits+=4;
		    $node .= "." if ($rbits < $bits);
		}
	    } else {
		$colon=1; # First colon in a row.
	    }
            
	  } else {
	    $colon=0;  # Not a colon
	    $node .= $_;
	    $rbits+=4;
	    $node .= "." if ($rbits < $bits);
	  } # else /:/
	}
      }
      printf ZONE "%s\t\tIN\tPTR\t%s\n", $node, $noderef->{name} . ".";
    }

  } else {
    # Forward pointers

    # "SELECT name FROM dns.ipname WHERE $zonere ~ name
    #   UNION SELECT name FROM dns.xzone WHERE $zonere ~* name;"
    $qh_nodes->execute("\\.".$zonere."\$", "\\.".$zonere."\$");
    while ( my $noderef=$qh_nodes->fetchrow_hashref )  {
      $noderef->{"name"} =~ /^(.*)\.$zonere/;
      my $node= $1;
      $nodeortab=$node;
      $nodeortab .= "\t" if (length $node < 8);

      # "SELECT * FROM dns.ipname where name = $name;"
      $qh_ipname->execute($noderef->{"name"});
      while ( my $rrs=$qh_ipname->fetchrow_hashref ) {
	my $type = ($rrs->{"ip_addr"} =~ /(\d+\.){3}\d+/ ) ? "A" : "AAAA";
	printf ZONE "%s\tIN\t%s\t%s\n", $nodeortab, $type, $rrs->{ip_addr};
	$nodeortab="\t";
      }

      # Add HINFO RRs
      $qh_hinfo->execute($noderef->{"name"});
      while ( my $rrs=$qh_hinfo->fetchrow_hashref ) {
	(my $hardware= $rrs->{"hardware"}) =~ s/[^ -~]//g;
	(my $os= $rrs->{"os"}) =~ s/[^ -~]//g;
	$hardware=~ s/[\\"]//g;
	$os=~ s/[\\"]//g;
        if ($hardware || $os ) {
	    printf ZONE "%s\tIN\tHINFO\t\"%s\" \"%s\"\n",
			$nodeortab,	$hardware, $os;
	    $nodeortab="\t";
        }
      }

      $qh_usr->execute($noderef->{"name"});
      while ( my $rrs=$qh_usr->fetchrow_hashref ) {
	(my $username= $rrs->{"username"}) =~ s/[^ -~]//g;
	$username=~ s/[\\"]//g;
	printf ZONE "%s\tIN\tTXT\t\"USR= %s\"\n", $nodeortab, $username;
	$nodeortab="\t";
      }
      $qh_loc->execute($noderef->{"name"});
      while ( my $rrs=$qh_loc->fetchrow_hashref ) {
	(my $bldg= $rrs->{"building"}) =~ s/[^A-Za-z0-9]//g;
	(my $room= $rrs->{"room"}) =~ s/[^ -~]//g;
	$room=~ s/[\\"]//g;
	printf ZONE "%s\tIN\tTXT\t\"LOC= %s %s\"\n", $nodeortab, $bldg, $room;
	$nodeortab="\t";
      }

      xzone($noderef->{name});



    }
  } 
  
  #close zone file, move into place
  close ZONE;
  rename $zoneprefix . $zone . ".tmp", $zoneprefix . $zone
	|| die "rename";  # If rename fails, bail -- dont reload

  # rndc reload $zone
  # rndc reload $dupezone{$zone}
  system ("/usr/sbin/rndc", "reload", $zone);
  if ($dupezone{$zone}) {
	system ("/usr/sbin/rndc", "reload", $dupezone{$zone});
  }

}
