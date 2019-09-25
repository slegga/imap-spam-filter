#!/usr/bin/env perl

use Mojo::Base -strict;
use Mail::IMAPClient;
use Carp;
use YAML::Tiny;
use autodie;
#use Data::Printer;
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
use SH::Email::ToHash;
use Data::Dumper;
use DateTime::Format::Mail;
use Hash::Merge 'merge';
use Digest::MD5 qw(md5_base64);
use Clone 'clone';
use Encode::Guess;
use Mojo::SQLite;
use Mojo::SQLite::Migrations;
use FindBin;
use Mojo::File;

binmode STDOUT, ':encoding(UTF-8)';
#use DateTime::Format::RFC3501;

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
    my $epoch = time;
	#
	#	SETUP database
	#

	my ($sqlite,$db);

    $sqlite = Mojo::SQLite->new($ENV{HOME} . '/etc/email.db');
    say $sqlite->db->query('select sqlite_version() as version')->hash->{version};
    # Use migrations to create a table
    my $tmp = path($FindBin::Bin)->to_array;
    pop @$tmp;
    my $project_dir = path(@$tmp);

    $sqlite->migrations->from_file($project_dir->child('migrations','email.sql')->to_string)->migrate(1);

    # Get a database handle from the cache for multiple queries
    $db = $sqlite->db;

    eval {

    open my $FH, '< :encoding(UTF-8)', $CONFIGFILE or die "Failed to read $CONFIGFILE: $!";
        $config_data = YAML::Tiny::Load(
            do { local $/; <$FH> }
        );    # slurp content
    } or do {
        confess $@;
    };

	for my $name (qw /banned_email_headers banned_ip_slices/)  {
	    my $file = $self->home->child("data/$name.yml");
	    if (-f "$file") {
	        eval {
	            open my $fh, '< :encoding(UTF-8)', "$file" or die "Failed to read $file: $!";
	            my $tmp = YAML::Tiny::Load( do { local $/; <$fh> } );
	            if (exists $config_data->{$name}) {
		            $config_data->{$name} = merge( $config_data->{$name}, $tmp);
		        } else {
		        	$config_data->{$name} = $tmp;
		        }
	        } or do {
	            confess $@;
	        };
	    }
	}

    if ($self->info) {
        print Dumper $config_data;
        return $self->gracefull_exit;
    }

    my $pf = DateTime::Format::Mail->new();
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
    	Peek     => 1,
    	) or die "Cant open $emc email account: ". ($config_data->{$emc}->{Server}//'__UNDEF__'). ' User: ' . ($config_data->{$emc}->{Username}//'__UNDEF');

    	say $imap->Rfc3501_datetime(time()) if defined $imap;
        my $folders = $imap->folders
        or die "$emc: List folders error: ", $imap->LastError, "\n";
#            printf "Folders: %s\n",join("\n",@$folders);

        my $convert = SH::Email::ToHash->new(tmpdir => '/tmp/emails');

        # WHITE LIST ALL EMAIL ADDRESS THAT IS WRITTEN TO
        my @all;
        my $last_read_sent_epoch=0;
        my $epoch_key = 'last_epoch_'.$config_data->{$emc}->{Server};
        #warn "epoch_key: $epoch_key";
        my @tmp = $db->query('SELECT value FROM variables WHERE key = ?',$epoch_key)->array;
        #warn "tmp @tmp";
        $last_read_sent_epoch = $tmp[0] if @tmp;
        $last_read_sent_epoch //=0;
        #warn "last_read_sent_epoch: $last_read_sent_epoch";
        my $current_read_sent_epoch=time;
        my %white_emailaddr = map{$_->{email} => 1} $db->query('SELECT email FROM whitelist_email_address')->hashes->each;
        $imap->select( $config_data->{$emc}->{Folder_Sent} ) or die "$emc: Select '$folders->[0]' error: ", $imap->LastError, "\n";
        @all =grep {$_} $imap->since($last_read_sent_epoch);
        #warn "Antall sent siden sist:".scalar @all;
        for my $uid(@all) {
            my $text = $imap->message_string($uid);
            my $email_h = $convert->msgtext2hash($text);
            my @emails=();
            if ($email_h->{header}->{To}) {
                @emails = map {$convert->extract_emailaddress($_)} split(/[\,]\s*/, $email_h->{header}->{To});
            }
            for my $e(@emails) {
                next if $e !~ /\@/;
                $db->query('REPLACE INTO whitelist_email_address(email) VALUES(?)', $e);
                $white_emailaddr{$e}=1;
            }
        }
        $db->query('REPLACE INTO variables(key,value)  values(?,?)',$epoch_key,$current_read_sent_epoch);

        # READ INBOX

    	$imap->select( 'INBOX' )
    	or die "$emc: Select '$folders->[0]' error: ", $imap->LastError, "\n";

    	@all = $imap->search('ALL')
    	or die "$emc: Fetch hash '$folders->[0]' error: ", $imap->LastError, "\n";
#        warn join(' ',@all);
        my %keep;
        my %spam;
        my $prev_email_h;
        my $t = localtime;
       my $curr_week = $t->week;
       my $curr_year = $t->year;

        my $weekword = $config_data->{$emc}->{weekword}|| 'uke';
        my $prefix =   $config_data->{$emc}->{weekword}|| 'Melding fra ';
        for my $uid(@all) {
            my $next = 0;
            my $text = $imap->message_string($uid);
            my $email_h = $convert->msgtext2hash($text);
            
            $email_h->{calculated}->{size} = $imap->size($uid);
            $email_h->{uid}=$uid;

            # Remove duplicated emails
            if ($prev_email_h && $email_h) {
                if ( exists $prev_email_h->{header}->{Date}
                &&   exists $email_h->{header}->{Date}
                && substr($prev_email_h->{header}->{Date},0,24) eq substr($email_h->{header}->{Date},0,24)
                && $prev_email_h->{header}->{Subject}           eq $email_h->{header}->{Subject}
                && $prev_email_h->{header}->{From}              eq $email_h->{header}->{From}
                && $prev_email_h->{header}->{'Return-Path'}     eq $email_h->{header}->{'Return-Path'}  ) {
                    my $move_uid;
                    $move_uid = $prev_email_h->{calculated}->{size} > $email_h->{calculated}->{size} ? $email_h->{uid} : $prev_email_h->{uid};
                    $spam{$move_uid} = "MOVE DUPLICATE ". $move_uid. '; '.$prev_email_h->{header}->{Subject};
                }

                #remove old weeks
                if ($email_h->{Subject} && $email_h->{Subject} =~/^$prefix.*$weekword.*\s(\d+)/i) {
                    my $sub_week = $1;
                    if ( $sub_week>0 ) {
                       my $week_diff = $curr_week - $sub_week;

                       # Try to handle new year
                       $week_diff -=52 if ( 47< $week_diff && $week_diff < 57  ) ;
                       if ($week_diff >0 && $week_diff < 5) {
                           $spam{$email_h->{uid}} = "MOVE PASSED WEEK ". $email_h->{uid} . ' Subject: '. $email_h->{Subject};
                       }
                   }
                }
            }
            $prev_email_h = clone $email_h;

            $email_h->{calculated}->{from} = $convert->extract_emailaddress($email_h->{header}->{From}) or next;
            for my $blocked_from(@{$config_data->{blocked_email}}) {
                next if ! $blocked_from;
                if ($email_h->{calculated}->{from} eq $blocked_from ) {
                    $spam{$uid} = 'blocked From '.$blocked_from. ';  '.$email_h->{header}->{Subject};
                    $next=1;
                    last;
                }
            }
            next if $next;
            
            # whitelist addresses after blacklist of addresses
            next if exists $white_emailaddr{$email_h->{calculated}->{from}} && $white_emailaddr{$email_h->{calculated}->{from}};
            #TODO: Some whitelisting of email adresses sent to or in address book
            # remove blocked email headers

            if (exists $config_data->{banned_email_headers}) {
                for my $key (keys %{$config_data->{banned_email_headers}}) {
                    for my $item (@{$config_data->{banned_email_headers}->{$key}}) {
                        next if ! $item;
                        next if not exists $email_h->{header}->{$key};
                        if (index($email_h->{header}->{$key},$item)>-1) {
                            $spam{$uid} = "banned_header_$key; $item; ". $email_h->{header}->{Subject};
                            $next=1;
                            last;
                        }
                    }
                }
            }

            next if $next;
            if (exists $config_data->{banned_body_regexp}) {
                for my $item (@{$config_data->{banned_body_regexp}}) {
                    next if ! $item;
                    last if ! exists $email_h->{body}->{content};
                    last if ! defined $email_h->{body}->{content};
                    if ( $email_h->{body}->{content} =~ /($item)/ ) {
                        $spam{$uid} = "banned_body_$item; $1; ".$email_h->{header}->{Subject};
                        $next=1;
                        last;
                    }
                }
            }
            next if $next;

            # delay remove of ads only on dates not datetimes
        	my $dt = time - 36 *60 *60;
            my ($res) = $email_h->{header}->{Received}->[0]->{a}->[1];
#            warn $res;
            $res =~s/^[\W]+//;
            $res =~s /\s*\(\w+\)$//;
            eval {
                $email_h->{calculated}->{received} = $pf->parse_datetime( $res )->epoch;
            };
            if ($@) {
                warn $res;
                warn Dumper $email_h->{header}->{Received};
                die $@;
            }
            die "Can not get Received date " .Dumper $email_h->{header}->{Received} if !$res;
            if ($dt > $email_h->{calculated}->{received}) {
            	for my $blocked(@{$config_data->{advertising_three_days}}) {
                    next if $blocked ne $email_h->{calculated}->{from};
                    $spam{$uid} = 'Ad after 3 days'. '  '.$email_h->{header}->{Subject};
            	}
            }

        	# delay remove of info emails
            $dt = time - 9 * 24 *60 *60;
            if ($dt > $email_h->{calculated}->{received}) {
            	for my $blocked(@{$config_data->{advertising_ten_days}}) {
                    next if $blocked ne $email_h->{calculated}->{from};
                    $spam{$uid} = 'Ad after 10 days'. '  '.$email_h->{header}->{Subject};
            	}
            }

            # newsletters
            $dt = time - 30 * 24 *60 *60;
            if ($dt > $email_h->{calculated}->{received}) {
            	for my $blocked(@{$config_data->{newsletters}}) {
                    next if $blocked ne $email_h->{calculated}->{from};
                    $spam{$uid} = 'newsletters  after 30 days'. '  '.$email_h->{header}->{Subject};
            	}
            }

            # remove finn notifiers after 3 days
            $dt = time - 3 * 24 *60 *60;
            if ($dt > $email_h->{calculated}->{received}) {
                for my $adrpart(@{$config_data->{socialmedia}}) {
                    next if $email_h->{calculated}->{from} !~qr{$adrpart};
                    $spam{$uid} = 'Remove soical media 3days'. '  '.$email_h->{calculated}->{from};
            	}
            }
            # 		#...; #TODO bruk SH::Email::ToHash
    		# 		#...;#todo NetAddr::IP: $me->contains($other)


        } #for uid

        if (keys %spam) {
            for my $uid(keys %spam) {
#            	my $decoder = Encode::Guess->guess($spam{$uid});
#            	warn "Problem decoding. Error message: $decoder\n$spam{$uid}\n" unless ref($decoder);
                print "$uid moved to spam ";
                print $spam{$uid} or die ord $spam{$uid};
                print "\n";
                $imap->move('INBOX.Spam',$uid);
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
