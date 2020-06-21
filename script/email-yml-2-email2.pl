#!/usr/bin/env perl

use Mojo::File 'path';

my $lib;
BEGIN {
    my $gitdir = Mojo::File->curfile;
    my @cats = @$gitdir;
    while (my $cd = pop @cats) {
        if ($cd eq 'git') {
            $gitdir = path(@cats,'git');
            last;
        }
    }
    $lib =  $gitdir->child('utilities-perl','lib')->to_string;
};
use lib $lib;
use SH::UseLib;
use SH::ScriptX;
use Mojo::Base 'SH::ScriptX';
use utf8;
use open ':encoding(UTF-8)';
use YAML::Tiny;
use Data::Dumper;

#use Carp::Always;

=encoding utf8

=head1 NAME

yml-conv-yml.pl - Convert old email.yml to email2.yml format

=head1 DESCRIPTION

<DESCRIPTION>

=cut

option 'dryrun!', 'Print to screen instead of doing changes';

sub main {
    my $self = shift;
    my @e = @{ $self->extra_options };
    my $new_data;
    die "Missing yml-filename" if !@e;
    my $infile= path(shift(@e));
    my $old_data = YAML::Tiny::LoadFile("$infile");
    
    for my $h1(keys %$old_data) {
        if ($h1 eq 'blocked_email') {
            $new_data->{blocked} = {expiration_days=>0,move_to=>'spam',criteria=>[]} if ! exists $new_data->{blocked};
            for my $from_is(@{ $old_data->{$h1} }) {
                push @{ $new_data->{blocked}->{criteria},  }, {from_is => $from_is};
            }
        }
        elsif ($h1 eq 'banned_body_regexp') {
            $new_data->{blocked} = {expiration_days=>0,move_to=>'spam',criteria=>[]} if ! exists $new_data->{blocked};
            for my $body_like(@{ $old_data->{$h1} }) {
                push @{ $new_data->{blocked}->{criteria},  }, {body_like => $body_like};
            }
        }
        elsif ($h1 eq 'banned_email_headers') {
            $new_data->{blocked} = {expiration_days=>0,move_to=>'spam',criteria=>[]} if ! exists $new_data->{blocked};
            for my $h2 (keys %{ $old_data->{$h1} }) {
                if ($h2 eq 'Subject') {
                    for my $subject_like(@{ $old_data->{$h1}->{$h2} }) {
                        push @{ $new_data->{blocked}->{criteria},  }, {subject_like => $subject_like};
                    }
                }
            }
        }
        elsif ($h1 eq 'advertising_three_days') {
            $new_data->{$h1} = {expiration_days=>2,move_to=>'spam',criteria=>[]};
            for my $from_is(@{ $old_data->{$h1} }) {
                push @{ $new_data->{$h1}->{criteria},  }, {from_is => $from_is};
            }
            
        }
        elsif ($h1 eq 'socialmedia') {
            $new_data->{$h1} = {expiration_days=>3,move_to=>'spam',criteria=>[]};
            for my $from_is(@{ $old_data->{$h1} }) {
                push @{ $new_data->{$h1}->{criteria},  }, {from_is => $from_is};
            }
            
        }
        elsif ($h1 eq 'advertising_ten_days') {
            $new_data->{$h1} = {expiration_days=>10,move_to=>'spam',criteria=>[]};
            for my $from_is(@{ $old_data->{$h1} }) {
                push @{ $new_data->{$h1}->{criteria},  }, {from_is => $from_is};
            }
            
        }
        elsif ($h1 eq 'newsletters') {
            $new_data->{$h1} = {expiration_days=>30,move_to=>'spam',criteria=>[]};
            for my $from_is(@{ $old_data->{$h1} }) {
                push @{ $new_data->{$h1}->{criteria},  }, {from_is => $from_is};
            }
            
        }
        elsif ($h1 eq 'keep_body_regexp') {
            $new_data->{keep} = {expiration_days=>10,move_to=>'inbox',criteria=>[]};
            for my $body_like(@{ $old_data->{$h1} }) {
                push @{ $new_data->{keep}->{criteria},  }, {body_like => $body_like};
            }
            
        }
        elsif ($h1 eq 'socialmedia') {
        }
        elsif ($h1 eq 'not_removed_not_in_use' ) {
            
        }
        elsif ( $h1 eq 'gmail.com' ||$h1 eq 'online.no') {
            $new_data->{connection}->{$h1} = $old_data->{$h1};
        }
        elsif ($h1 eq 'userfolder_subject_regexp') {
            for my $folder (keys %{ $old_data->{$h1} }) {
                my $name = "move_to_$folder";
                $new_data->{$name} = {expiration_days=>9,move_to=>$folder,criteria=>[]};
                for my $subject_like(@{ $old_data->{$h1}->{$folder} }) {
                    push @{ $new_data->{$name}->{criteria},  }, {subject_like => $subject_like};
                }
            }
        }
        elsif ($h1 eq 'userfolder_from_email_address') {
            for my $folder (keys %{ $old_data->{$h1} }) {
                my $name = "move_to_$folder";
                $new_data->{$name} = {expiration_days=>9,move_to=>$folder,criteria=>[]};
                for my $from_is(@{ $old_data->{$h1}->{$folder} }) {
                    push @{ $new_data->{$name}->{criteria},  }, {from_is => $from_is};
                }
            }
        }
    
        else { 
            say Dump $old_data->{$h1};
            die $h1;
        }
    }
    say Dump $new_data;

}

__PACKAGE__->new(options_cfg=>{extra=>1})->main();
