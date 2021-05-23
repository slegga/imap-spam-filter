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
use Test::Mail::IMAPClient;
no warnings qw(experimental::signatures);

binmode STDOUT, ':encoding(UTF-8)';
binmode STDIN, ':encoding(UTF-8)';

=head1 NAME

imap-spam-filter.pl - Clean email

=head1 DESCRIPTION

Script for cleaning your email account.

=cut

# Find and manage the project root directory
has home => sub { path($0)->sibling('..') };
option 'verbose!', 'Turn on verbose output';
option 'debug!', 'Turn on debug output';
option 'regexp=s', 'Regexp on email. Mainly for debugging purposes';
option 'info!',  'Print out config data. And exit';
option 'server=s', 'regexp på server name, for running only one or few not all';


has 'configfile'=> $ENV{HOME} . '/etc/email2.yml';

# calculate rule order for sort. Return a value for sorting
sub orderval {
    my  ($self, $rule_hr) = @_;
    my $return  = $rule_hr->{expiration_days} * 10000;
    $return -= 10 if exists $rule_hr->{whitelist};
    if (exists $rule_hr->{move_to}) {
        $return += 10;
        if ($rule_hr->{move_to} =~ /spam/i) {
            $return += 1;
        }
    }
    for my $crit (@{ $rule_hr->{criteria} }) {
        $return += 1 if grep {$_ =~/\_(contain|in|like)$/} keys %$crit;
    }
    return  $return;
}

sub main {

    #
    #   Gather info
    #

   my $self = shift;

    my $CONFIGFILE = $self->configfile;
    my $config_data;
    my $test_return;
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

#    $sqlite->migrations->from_file($project_dir->child('migrations','email.sql')->to_string)->migrate(1);

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

    if($ENV{MOCK} ) {
        say "MOCK";
        return 1;
    }

	for my $name (qw /banned_email_headers banned_ip_slices/)  {
	    my $file = $self->home->child("data/$name.yml");
	    if (-f "$file") {
	        eval {
	            open my $fh, '< :encoding(UTF-8)', "$file" or die "Failed to read $file: $!";
	            my $tmp = YAML::Tiny::Load( do { local $/; <$fh> } );
                $config_data->{blocked} = {expiration_days=>0,move_to=>'INBOX.Spam',criteria=>[]} if ! exists $config_data->{blocked};
                #say ref($tmp) ."   $name";
                #say Dump $tmp;
                if ($name eq 'banned_email_headers') {
                    for my $h3 (keys %$tmp ) {
                        for my $h4(@{ $tmp->{$h3} }) {
                            push @{ $config_data->{blocked}->{criteria},  }, {$h3."_contain" => $h4};
                        }
                    }
                }
                elsif($name eq 'banned_ip_slices') {
                    for my $h2 (@$tmp) {
                        push @{ $config_data->{blocked}->{criteria},  }, {ip_address_in => $h2};
                    }
                } else {die "Unknown name $name"}
                1;
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
    for my $emc( grep {ref $config_data->{connection}->{$_} eq 'HASH'} keys %{ $config_data->{connection} }) {
        if  ($self->server) {
            my $s = $self->server;
            next if $emc!~/$s/;
        }
        my %connect =(    	Server   => $config_data->{connection}->{$emc}->{Server},
    	User     => $config_data->{connection}->{$emc}->{Username},
    	Password => $config_data->{connection}->{$emc}->{Password},
    	Ssl      => $config_data->{connection}->{$emc}->{Ssl},
    	Uid      => $config_data->{connection}->{$emc}->{Uid},
    	Debug    => $config_data->{connection}->{$emc}->{Debug},
    	Peek     => 1,);

#say Dumper \%connect;
    	my $imap;
    	if($connect{Server} eq 'files') {
    	    $connect{$_} = $config_data->{connection}->{$emc}->{$_} for (keys %{$config_data->{connection}->{$emc}});
    	    $imap = Test::Mail::IMAPClient->new(%connect);
    	}
    	else {
    	    $imap = Mail::IMAPClient->new(%connect) or die "Cant open $emc email account: ". ($config_data->{$emc}->{Server}//'__UNDEF__'). ' User: ' . ($config_data->{$emc}->{Username}//'__UNDEF')."ERROR: $@";
        }
    	say $imap->Rfc3501_datetime(time()) if defined $imap;
#    	$imap->connect or die "Could not connect: $@\n";
        my $folders = $imap->folders
        or die "$emc: List folders error: ", $imap->LastError, "\n". Dumper \%connect;;
#        printf "Folders: %s\n",join("\n",@$folders);

        my $convert = SH::Email::ToHash->new(tmpdir => '/tmp/emails');

        # WHITE LIST ALL EMAIL ADDRESS THAT IS WRITTEN TO
        my @all;
        my $last_read_sent_epoch=0;
        my $epoch_key = 'last_epoch_'.$config_data->{connection}->{$emc}->{Server};
        #warn "epoch_key: $epoch_key";
        my @tmp = $db->query('SELECT value FROM variables WHERE key = ?',$epoch_key)->array;
        #warn "tmp @tmp";
        $last_read_sent_epoch = $tmp[0] if @tmp;
        $last_read_sent_epoch //=0;
        #warn "last_read_sent_epoch: $last_read_sent_epoch";
        my $current_read_sent_epoch=time;
        my %white_emailaddr = map{$_->{email} => 1} $db->query('SELECT email FROM whitelist_email_address')->hashes->each;
        say $config_data->{connection}->{$emc}->{Folder_Sent} ;
        $imap->select( $config_data->{connection}->{$emc}->{Folder_Sent} ) or die "$emc: Select '".($config_data->{connection}->{$emc}->{Folder_Sent}//'__UNDEF__')."' error: ", $imap->LastError, "\n";
        @all =grep {$_} $imap->since($last_read_sent_epoch);
#        warn "Antall sent siden sist:".scalar @all;

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
        my %action;
        my %userfolders;
        my $prev_email_h;
        my $t = localtime;
       my $curr_week = $t->week;
       my $curr_year = $t->year;

        my $weekword = $config_data->{connection}->{$emc}->{weekword}|| 'uke';
        my $prefix =   $config_data->{connection}->{$emc}->{weekword}|| 'Melding fra ';

        #MAIN LOOP
        my @rules = sort{$self->orderval($config_data->{$b}) <=> $self->orderval($config_data->{$a})}  grep {exists $config_data->{$_}->{expiration_days}} keys %$config_data;

        for my $uid(@all) {
            my $next = 0;
            my $text = $imap->message_string($uid);
            if (my $re = $self->regexp) {
                next if $text !~ /$re/;
                $DB::single=2;
            }
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
                    $action{$move_uid} = {rule=>"MOVE DUPLICATE ", action =>'move_to',folder=>'INBOX.Spam', email_name=>$prev_email_h->{header}->{Subject} };
                }

                #remove old weeks
                if ($email_h->{Subject} && $email_h->{Subject} =~/^$prefix.*$weekword.*\s(\d+)/i) {
                    my $sub_week = $1;
                    if ( $sub_week>0 ) {
                       my $week_diff = $curr_week - $sub_week;

                       # Try to handle new year
                       $week_diff -=52 if ( 47< $week_diff && $week_diff < 57  ) ;
                       if ($week_diff >0 && $week_diff < 5) {
                           $action{$email_h->{uid}} ={ rule=>"MOVE PASSED WEEK ",  email_name => $email_h->{Subject}};
                       }
                   }
                }
            }
            $prev_email_h = clone $email_h;
            {
                my $from = $email_h->{header}->{From} || $email_h->{header}->{'Return-Path'};
                $email_h->{calculated}->{from} = $convert->extract_emailaddress($from)  or next;
            }
            # delay remove of ads only on dates not datetimes
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


            # LOOP over rules
            for my $rule( @rules ) {
                next if $rule eq 'connection';
                last if $next==1;
                my $dt = time - $config_data->{$rule}->{expiration_days} * 24 *60 *60;
                next if ($dt < $email_h->{calculated}->{received});
                for my $crit (@{ $config_data->{$rule}->{criteria} }) {
                    my $hit = 0;
                    for my $v(keys %$crit) {
                        if ($v eq 'from_is') {
                            if ($email_h->{calculated}->{from} eq $crit->{$v}) {
                                $action{$uid}{reason} .= $v;
                                $hit=1;
                            } else { $hit=0;last; }
                        } elsif ($v eq 'from_like') {
                            my $qr = qr($crit->{$v});
                            if ($email_h->{calculated}->{from} =~ /$qr/) {
                                $action{$uid}{reason} .= join (' ',$v,$email_h->{calculated}->{from},'=~', $crit->{$v});
                                $hit=1;
                            } else { $hit=0;last }
                        } elsif ($v eq 'from_not_like') {
                            my $qr = qr($crit->{$v});
                            if ($email_h->{calculated}->{from} !~ /$qr/) {
                                $action{$uid}{reason} .= join (' ',$v,$email_h->{calculated}->{from},'!~', $crit->{$v});
                                $hit=1;
                            } else { $hit=0;last }
                        } elsif ($v eq 'body_like') {
                            my $qr = qr/($crit->{$v})/;
                            if (! exists $email_h->{body}->{content}) {
                                $hit=0;last;
                            }
                            if (! $email_h->{body}->{content}) {
                                $hit=0; last;
                            }
                            if ($email_h->{body}->{content} =~ /$qr/) {
                                $action{$uid}{reason} .= $v.' '. $1. "=~". $qr;
                                $hit=1;
                            } else { $hit=0;last }
                        } elsif ($v eq 'subject_like') {
                            my $qr = qr/($crit->{$v})/;

                            if ($email_h->{header}->{Subject} && $email_h->{header}->{Subject} =~ /$qr/) {
                                $action{$uid}{reason} .= $v.' '. $1;
                                $hit=1;
                            } else { $hit=0;last }
                        } elsif ($v eq 'subject_not_like') {
                            my $qr = qr/($crit->{$v})/;

                            if ($email_h->{header}->{Subject} && $email_h->{header}->{Subject} !~ /$qr/) {
                                $action{$uid}{reason} .= $v.' '. ($1//'');
                                $hit=1;
                            } else { $hit=0;last }
                        } elsif ($v eq 'subject_like') {
                            my $qr = qr/($crit->{$v})/;

                            if ($email_h->{header}->{Subject} && $email_h->{header}->{Subject} =~ /$qr/) {
                                $action{$uid}{reason} .= $v.' '. $1;
                                $hit=1;
                            } else { $hit=0;last }
                        } elsif ($v =~ /(.+)_contain$/) {
                            my $header= $1;
                            my $part = $crit->{$v};
                            if (!exists $email_h->{header}->{$header}) {
                                $hit=0; last;
                            }
                            if (! $email_h->{header}->{$header}) {
                                $hit=0; last;
                            }
                            if (index($email_h->{header}->{$header},$part)>-1) {
                                $action{$uid}{reason} .= $v.' '.'$header like' .$part;
                                $hit=1;
                            } else { $hit=0;last }
                        } elsif ($v eq 'ip_address_in') {
                            my $slice = $crit->{$v};
                            my $ip = $email_h->{header}->{'X-XClient-IP-Addr'};
                            if (
                            NetAddr::IP->new($ip)->within(NetAddr::IP->new($slice)) ) {
                                $action{$uid}{reason} .= join(' ',$v,$ip,'part of',$slice);
                                $hit=1;
                            } else { $hit=0;last }
                        } else {
                            die "Unsupported keyword $v at $rule ".Dump $crit;
                        }
                    }
                    if ($hit) {
                        if (exists $config_data->{$rule}->{whitelist}) {
                            delete $action{$uid};
                        }
                        elsif (exists $config_data->{$rule}->{move_to}) {
                            $action{$uid}{rule}  = $rule;
                            $action{$uid}{action}='move_to';
                            $action{$uid}{folder}= $config_data->{$rule}->{move_to};
                            $action{$uid}{email_name}=$email_h->{header}->{Subject};
                        } else {
                            warn "$_ = ".$config_data->{$rule}->{$_} for  grep{$_ ne 'criteria'} keys %{$config_data->{$rule}};
                            die "Do not what to do $rule";
                        }

                        $next=1;
                        last;

                    }
                    $action{$uid}{reason}=undef;
                }
            }

        } #for uid

        if (keys %action) {

            for my $uid(keys %action) {
            	# my $decoder = Encode::Guess->guess($action{$uid});
            	# warn "Problem decoding. Error message: $decoder\n$action{$uid}\n" unless ref($decoder);
                if ($action{$uid}{action} && $action{$uid}{action} eq 'move_to') {
                    print  Dumper $action{$uid} or die ord $action{$uid};
                    print "\n";
                    print "$uid moved to $action{$uid}{folder} ";
                    $imap->move($action{$uid}{folder},$uid);
                }
            }
        }


    	#SH::PrettyPrint::print_hashes \@hashes;

    	# TODO: Only keep 1 or x of emails from this sender.

    	$test_return = $imap->expunge;
    	$imap->logout
    	    or die "Logout error: ", $imap->LastError, "\n";
    } #connection
    return $test_return;
} # main

__PACKAGE__->new->main;
