use strict;
use warnings; 
use Image::Grab;
use Net::Twitter;
use File::Slurp;
use MIME::Base64;
use Data::Dumper;
use HTML::Entities;

require "apiconfig.pl";

# the ID of the last Tweet we cloned
my $lastid = "";

# the filename to store the ID
my $lastidFilename = "joelastid.txt";

# the max number of tweets to download
my $lastTweetsCount = 10;

# number of seconds to sleep between Tweets
my $sleep = 2; 

# some set up for the Twitter API
$ENV{PERL_LWP_SSL_VERIFY_HOSTNAME} = 0;
binmode STDOUT, ":utf8";

# the Joe friend and Joe clone accounts as configured in apiconfig.pl
my $joefriend = getJoeFriend();
my $joeclone = getJoeClone();

# read the lastid from the text file
if (-e $lastidFilename)
{
    open my $readfile, '<', "$lastidFilename"; 
    $lastid = <$readfile>;
    chomp $lastid; 
    close $readfile;
}

eval 
{
    # the statuses hash in which the updates will be stored
    my $statuses;
    
    # if $lastid != then download the last X tweets since that id, otherwise just download 
    # the last X tweets in general
    if (length($lastid) > 0)
    {
        print "downloading tweets since last id : [" . $lastid . "]\n"; 
        $statuses = $joefriend->user_timeline({screen_name=>'josephcumia', since_id=>$lastid, count=>1});
    }
    else
    {
        print "no last id, downloading $lastTweetsCount tweets manually\n";
        $statuses = $joefriend->user_timeline({screen_name=>'josephcumia', count=>$lastTweetsCount});
    }
    
    print "number of joe tweets downloaded: " . @$statuses . "\n\n";
    print "Starting re-posting.............\n\n";
    
    # loop through all the Tweets we just downloaded
    for my $status (reverse @$statuses) 
    {
        print "--------------------------------\n"; 
        print "ORG tweet id   : " . $status->{id} . "\n";
        print "ORG tweet date : " . $status->{created_at} . "\n";
        print "ORG text text  : " . $status->{text} . "\n";    

        # this is our new last id
        $lastid = $status->{id};
        
        # the current text of the Tweet we're preparing
        my $text = $status->{text};
        
        # array of @-mentions to block and unblock
        my @mentions;
        
        # extra info added to a new tweet
        my $extrainfo;
        
        # see if there were any media entities and if we need to loop through them
        if (exists $status->{extended_entities} && exists $status->{extended_entities}->{media})
        {         
            print "ORG # of media : " . @{$status->{extended_entities}->{media}} . "\n";
            
            # NOTE: the reverse here assumes that the media links in the Tweet occur in order
            # so we reverse the media array so that we can stil use the indicies
            for my $media (reverse @{$status->{extended_entities}->{media}})
            {
                # make sure this is a photo
                next unless $media->{type} eq 'photo';
                
                # remove the http://t.co/XXXXXX link from the tweet according to the indicies
                my $startidx = $media->{indices}[0];
                my $endidx = $media->{indices}[1];
                my $length = $endidx - $startidx;
                
                substr($text, $startidx, $length, "");
                chomp $text;
                chop $text;                
                                
                # the filename to which we will save the file        
                my $filename = "image.jpg";
                                
                # download the image
                my $pic = new Image::Grab;
                $pic->url($media->{media_url});
                $pic->grab;
                open(IMAGE, ">$filename") || die"$filename: $!";
                binmode IMAGE;  # for MSDOS derivations.
                print IMAGE $pic->image;
                close IMAGE;
                
                # read the image file 
                my $file_contents = read_file ($filename , binmode => ':raw');
                
                # delete the image file we downloaded
                unlink $filename;
                
                # upload the image as a media file
                my $mediastatus = $joeclone->upload(encode_base64($file_contents));
                #print "NEW media id   : [". $mediastatus->{media_id} ."]\n";

                # push the media id to our array
                push @{$extrainfo->{media_ids}}, $mediastatus->{media_id};
                
                # TODO: There is bug when there are more than two media elements in that
                # they are not getting reposted correctly, so we will only support reposting
                # of one media element for now
                last;
            }
        }
       
        # build an array of people mentioned in the Tweet that will get blocked and unblocked
        if (defined $status->{entities} && defined $status->{entities}->{user_mentions})
        {
            for my $mention (@{$status->{entities}->{user_mentions}})
            {
                push @mentions, $mention->{id};
            }
        }        
        
        # see if this tweet is a reply to another one, if so then set the reply-to info
        # and add the user to the block/unblock list
        if (defined $status->{in_reply_to_status_id} && defined $status->{in_reply_to_user_id_str})
        {
            $extrainfo->{in_reply_to_status_id} = $status->{in_reply_to_status_id};
            push @mentions, $status->{in_reply_to_user_id_str};
        }   
        
        # send the tweet with the media file
        eval 
        {
            print Dumper @mentions;
            print ("NEW text    : [" . $text . "]\n");
            print ("NEW media # : " . (exists $extrainfo->{media_ids} ? @{$extrainfo->{media_ids}} : 0) . "\n");

            # block any users in the tweet so that they don't get 
            # a notification about @-mention
            for my $m (@mentions)
            {
                print ("blocking: $m\n");
                $joeclone->create_block({user_id=>$m});
            }      
            
            # add the Tweet text to our information hash
            $extrainfo->{status} = decode_entities($text);
            
            # flatten the mediaids if we need to
            if (defined $extrainfo->{media_ids} && scalar @{$extrainfo->{media_ids}} == 1)
            {
                $extrainfo->{media_ids} = $extrainfo->{media_ids}[0];
            }
 
            # now that all our info and everything is good to go, go ahead and post it!
            my $result = $joeclone->update($extrainfo);
            # print Dumper $result;
            
            # unblock any @-mentions because this is a troll we want 
            # everyone to see!
            for my $m (@mentions)
            {
                print ("unblocking: $m\n");
                $joeclone->destroy_block({user_id=>$m});
            }                 
            
            if (exists $result->{id})
            {
                print 'Posted new Tweet with ID: ['. $result->{id} ."])\n";
                print "Sleeping for [$sleep] seconds\n";
                sleep $sleep; 
            }
            else
            {
                # TODO: better error reporting
                print 'No $result->{id} was returned retweeting: ['. $lastid ."]\n";
                sleep $sleep; 
            }
        };       
        
        print "--------------------------------\n"; 
    }
};

print "new last: [" . $lastid . "]\n";

# write the last id to the file
open my $writefile, '>', "$lastidFilename"; 
print $writefile "$lastid\n";
close $writefile;
