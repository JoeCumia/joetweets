#!/usr/bin/perl
use strict;
use warnings;

# Twitter API info for Joe's friend (the account that can read Joe's Tweets)
my $joefriend = Net::Twitter->new(
    consumer_key        => '',
    consumer_secret     => '',
    access_token        => '',
    access_token_secret => '',
    ssl                 => 1,
    traits   => [qw/API::RESTv1_1/],
);

# Twitter API info for the destination (the account to which the Tweets will be cloned)
my $joeclone = Net::Twitter->new(
    consumer_key        => '',
    consumer_secret     => '',
    access_token        => '',
    access_token_secret => '',
    ssl                 => 1,
    traits   => [qw/API::RESTv1_1/],
);

sub getJoeFriend() { return $joefriend; };
sub getJoeClone() { return $joeclone; };

1;