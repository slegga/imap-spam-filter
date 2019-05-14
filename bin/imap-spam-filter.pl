#!/usr/bin/env perl

use Mojo::Base -strict;
use Mail::IMAPClient;
use Carp;
use YAML::Tiny;
use autodie;
use Data::Printer;
use Mojo::JSON 'to_json';
use Mojo::File 'path';
use Carp::Always;
use FindBin;
use lib "$FindBin::Bin/../../utilities-perl/lib";
use SH::UseLib;
use SH::PrettyPrint;
use SH::ScriptX; # call SH::ScriptX->import
use Mojo::Base 'SH::ScriptX';
use Time::Piece;
use NetAddr::IP;

=head1 NAME

imap-spam-filter.pl

=cut

# Find and manage the project root directory
has home => sub { path($0)->sibling('..') };
option 'verbose!', 'Turn on verbose output';
option 'debug!', 'Turn on debug output';
option 'info!',  'Print out config data. And exit';
option 'server=s', 'regexp på server name, for running only one or few not all';

sub main {

    #
    #   Gather info
    #

   my $self = shift;

    my $CONFIGFILE = $ENV{HOME} . '/etc/email.yml';
    my $config_data;

    eval {
        open my $FH, '< :encoding(UTF-8)', $CONFIGFILE or die "Failed to read $CONFIGFILE: $!";
        $config_data = YAML::Tiny::Load(
            do { local $/; <$FH> }
        );    # slurp content
    } or do {
        confess $@;
    };

    my $ban_heads = $self->home->child('data/banned_email_headers.yml');
    if (-f "$ban_heads") {
        eval {
            open my $fh, '< :encoding(UTF-8)', "$ban_heads" or die "Failed to read $ban_heads: $!";
            $config_data->{banned_email_headers} = YAML::Tiny::Load( do { local $/; <$fh> } );
        } or do {
            confess $@;
        };
    }
    if ($self->info) {
        p $config_data ;
        return $self->gracefull_exit;
    }

    for my $emc( grep {ref $config_data->{$_} eq 'HASH'} keys %$config_data) {
    	next if $emc eq 'banned_email_headers';
    	next if $emc eq 'advertising_three_days';
    	next if $emc eq 'blocked_email';
    	next if $emc eq 'advertising_ten_days';
        if  ($self->server) {
            my $s = $self->server;
            next if $emc!~/$s/;
        }
    	my $imap = Mail::IMAPClient->new(
    	Server   => $config_data->{$emc}->{Server},
    	User     => $config_data->{$emc}->{Username},
    	Password => $config_data->{$emc}->{Password},
    	Ssl      => $config_data->{$emc}->{Ssl},
    	Uid      => $config_data->{$emc}->{Uid},
    	Debug    => $config_data->{$emc}->{Debug},
    	) or die "Cant open $emc email account: ". ($config_data->{$emc}->{Server}//'__UNDEF__'). ' User: ' . ($config_data->{$emc}->{Username}//'__UNDEF');

    	say $imap->Rfc3501_datetime(time()) if defined $imap;

    	my $folders = $imap->folders
    	or die "$emc: List folders error: ", $imap->LastError, "\n";
#    	printf "Folders: %s\n",join("\n",@$folders);

    	$imap->select( 'INBOX' )
    	or die "$emc: Select '$folders->[0]' error: ", $imap->LastError, "\n";

    	$imap->fetch_hash("FLAGS", "INTERNALDATE", "RFC822.SIZE")
    	or die "$emc: Fetch hash '$folders->[0]' error: ", $imap->LastError, "\n";


    	# remove blocked senders
    	for my $blocked(@{$config_data->{blocked_email}}) {
    	    my $uid_ar = $imap->search( 'FROM "'.$blocked.'"' ) or warn "search failed: $@\n";
    	    if (@$uid_ar) {
    	        say to_json($uid_ar);
    	        $imap->move('INBOX.Spam',$uid_ar);
    	    }
    	}

    	# remove blocked email headers
    	for my $key (keys %{$config_data->{banned_email_headers}}) {
    	    for my $item (@{$config_data->{banned_email_headers}->{$key}}) {
    	        #say "head: $key -> $item";

    	        my $uid_ar = $imap->search( HEADER => $key => \$imap->Quote($item) ) or warn "search failed: $@\n";
    	        if (defined $uid_ar && @$uid_ar) {
				#...; #TODO bruk SH::Email::ToHash
				#...;#todo NetAddr::IP: $me->contains($other)
    		        say "MOVE TO SPAM BANNED: $key -> $item";
    	#            p($uid_ar);
    	            $imap->move('INBOX.Spam',$uid_ar);
    	        }
    	    }
    	}
        for my $netslice (@{$config_data->{banned_ip_slices}}) {
        }


    	# delay remove of ads only on dates not datetimes
    	my $dt = time - 36 *60 *60;

    	for my $blocked(@{$config_data->{advertising_three_days}}) {
    	    my $search = 'FROM "'.$blocked.'" BEFORE '.$imap->Rfc3501_date($dt);#45646545644"';#.$imap->Quote($imap->Rfc3501_datetime($dt));#Rfc822_date($dt));
    	    #say "###$search";
    	    my $uid_ar = $imap->search( $search ) or warn "search failed: $@\n";
    	    if (defined $uid_ar && @$uid_ar) {
    	        say "WARNING MOVE ADS TO SPAM";
    	#        p($uid_ar);
    	        $imap->move('INBOX.Spam',$uid_ar);
    	    }

    	}

    	# delay remove of info emails
    	 $dt = time - 9 * 24 *60 *60;

    	for my $blocked(@{$config_data->{advertising_ten_days}}) {
    	    my $search = 'FROM "'.$blocked.'" BEFORE '.$imap->Rfc3501_date($dt);#45646545644"';#.$imap->Quote($imap->Rfc3501_datetime($dt));#Rfc822_date($dt));
    	#    say "###$search";
    	    my $uid_ar = $imap->search( $search ) or warn "search failed: $@\n";
    	    if (defined $uid_ar && @$uid_ar) {
    	        say "WARNING MOVE INFO TO SPAM";
    	#        p($uid_ar);
    	        $imap->move('INBOX.Spam',$uid_ar);
    	    }

    	}

    	# Remove duplicated emails
    	my @all = $imap->messages;
    	my $hashref = $imap->parse_headers(\@all, #"ALL"
    	 "Date","Subject","Return-Path","From"
    	)  or die "Could not parse_headers: $@\n";
    	my @hashes;
    	while (my ($key,$value) = each %$hashref) {
    		my $return={};
    		$return->{uid} = $key;
    		for my $k(keys %$value) {
    			$return->{$k} = $value->{$k}->[0];
    		}
    		$return->{size} = $imap->size($return->{uid});
    		push @hashes, $return;
    	}
    	@hashes = sort{ $a->{uid} <=> $b->{uid} } @hashes;
    	my $t = localtime;
    	my $curr_week = $t->week;
    	my $curr_year = $t->year;
    	my $weekword = $config_data->{$emc}->{weekword}|| 'uke';
    	my $prefix =   $config_data->{$emc}->{weekword}|| 'Melding fra ';
    	my $prev_email;
    	for my $email(@hashes) {
    		if ($prev_email) {
    			if (substr($prev_email->{Date},0,24) eq substr($email->{Date},0,24) && $prev_email->{Subject} eq $email->{Subject} && $prev_email->{From} eq $email->{From} && $prev_email->{'Return-Path'} eq $email->{'Return-Path'}  ) {
    	#			p $email;
    	#			p $prev_email;

    				my $move_uid = $prev_email->{size} > $email->{size} ? $email->{uid} : $prev_email->{uid};
    				say "MOVE DUPLICATE ". $move_uid;
    				$imap->move('INBOX.Spam',$move_uid);
    			}
    		}
    		$prev_email = $email;
    		if ($email->{Subject} && $email->{Subject} =~/^$prefix.*$weekword.*\s(\d+)/i) {
    			my $sub_week = $1;
    			if ( $sub_week>0 ) {
    				my $week_diff = $curr_week - $sub_week;

    				# Try to handle new year
    				$week_diff -=52 if ( 47< $week_diff && $week_diff < 57  ) ;

    				if ($week_diff >0 && $week_diff < 5) {
    					say "MOVE PASSED WEEK ". $email->{uid} . ' Subject: '. $email->{Subject};
    					$imap->move( 'INBOX.Spam',$email->{uid} );
    				}
    			}
    		}
    	}

    	#SH::PrettyPrint::print_hashes \@hashes;

    	# TODO: Only keep 1 or x of emails from this sender.

    	$imap->expunge;
    	$imap->logout
    	    or die "Logout error: ", $imap->LastError, "\n";
    }


}

__PACKAGE__->new->main;
