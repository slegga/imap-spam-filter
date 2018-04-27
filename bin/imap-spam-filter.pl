#!/usr/bin/env perl

use Mojo::Base -strict;
use Mail::IMAPClient;
use Carp;
use YAML;
use Data::Printer;

my $CONFIGFILE = $ENV{HOME} . '/etc/email.yml';
my $config_data;

eval {
    open my $FH, '< :encoding(UTF-8)', $CONFIGFILE or die "Failed to read $CONFIGFILE: $!";
    $config_data = YAML::Load(
        do { local $/; <$FH> }
    );    # slurp content
} or do {
    confess $@;
};

  my $imap = Mail::IMAPClient->new(
    Server   => $config_data->{mail_server},
    User     => $config_data->{username},
    Password => $config_data->{password},
    Ssl      => 1,
    Uid      => 1,
  );

  my $folders = $imap->folders
    or die "List folders error: ", $imap->LastError, "\n";
  print "Folders: @$folders\n";

  $imap->select( $folders->[0] )
    or die "Select '$folders->[0]' error: ", $imap->LastError, "\n";

  $imap->fetch_hash("FLAGS", "INTERNALDATE", "RFC822.SIZE")
    or die "Fetch hash '$folders->[0]' error: ", $imap->LastError, "\n";

for my $blocked(@{$config_data->{blocked_email}}) {
    my $uid_ar = $imap->search( 'FROM "'.$blocked.'"' ) or warn "search failed: $@\n";
    p($uid_ar);  
    $imap->move('INBOX.Spam',$uid_ar);
}
$imap->expunge;
$imap->logout
    or die "Logout error: ", $imap->LastError, "\n";
