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
use SH::Email::ToHash;
use Data::Dumper;
use DateTime::Format::Mail;
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
	            $config_data->{$name} = YAML::Tiny::Load( do { local $/; <$fh> } );
	        } or do {
	            confess $@;
	        };
	    }
	}

    if ($self->info) {
        p $config_data ;
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
#    	printf "Folders: %s\n",join("\n",@$folders);

    	$imap->select( 'INBOX' )
    	or die "$emc: Select '$folders->[0]' error: ", $imap->LastError, "\n";

    	my @all = $imap->search('ALL')
    	or die "$emc: Fetch hash '$folders->[0]' error: ", $imap->LastError, "\n";

#        warn join(' ',@all);
		my $convert = SH::Email::ToHash->new;
        my %keep;
        my %spam;
        for my $uid(@all) {
            my $next = 0;
            my $text = $imap->message_string($uid);
            my $email_h = $convert->msgtext2hash($text);
#            printf "%s\t%s\t%s\t%s\n",$uid,$email_h->{header}->{From}, $email_h->{header}->{'Return-Path'},$email_h->{header}->{Subject};
            $email_h->{calculated}->{from} = $convert->extract_emailaddress($email_h->{header}->{From});
            for my $blocked_from(@{$config_data->{blocked_email}}) {
                if ($email_h->{calculated}->{from} eq $blocked_from ) {
                    $spam{$uid} = 'blocked From';
                    $next=1;
                    last;
                }
            }
            next if $next;

            #TODO: Some whitelisting of email adresses sent to or in address book
            # remove blocked email headers
        	for my $key (keys %{$config_data->{banned_email_headers}}) {
        	    for my $item (@{$config_data->{banned_email_headers}->{$key}}) {
        	        #say "head: $key -> $item";

        	        #my $uid_ar = $imap->search( HEADER => $key => \$imap->Quote($item) ) or warn "search failed: $@\n";
                    next if ! $item;
                    next if not exists $email_h->{header}->{$key};
                    if (index($email_h->{header}->{$key},$item)>-1) {
                        $spam{$uid} = "banned_header_$key";
                        $next=1;
                        last;
                    }
        	    }
        	}

            # delay remove of ads only on dates not datetimes
        	my $dt = time - 36 *60 *60;
            my ($res) = $email_h->{header}->{Received}->[0]->{a}->[1];
#            warn $res;
            $res =~s/^[\W]+//;
            $res =~s /\s*\(\w+\)$//;
#            warn $res;
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
                    next if $blocked ne $email_h->{calculated}->{received};
                    $spam{$uid} = 'Ad after 3 days';
            	}
            }

        	# delay remove of info emails
            $dt = time - 9 * 24 *60 *60;
            if ($dt > $email_h->{calculated}->{received}) {
            	for my $blocked(@{$config_data->{advertising_three_days}}) {
                    next if $blocked ne $email_h->{calculated}->{received};
                    $spam{$uid} = 'Ad after 10 days';
            	}
            }



            # 		#...; #TODO bruk SH::Email::ToHash
    		# 		#...;#todo NetAddr::IP: $me->contains($other)

        }
        if (keys %spam) {
            p %spam;
            for my $uid(keys %spam) {
                say "$uid moved to spam ".$spam{$uid};
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
