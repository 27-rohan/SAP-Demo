package ariba::Automation::ConfigWriter;

#
# Generate robot.conf.local
#
# TODO: Generate global.actionSequence
# TODO: Pull list of product/releases from constants somewhere
# TODO: Consider generating schedule for LQ robots
# TODO: Rename actions with hawk/10s2 in them (e.g. action.hawk-buildname-from-label)
#

use strict;
use warnings;
use File::Copy;
use POSIX;
use ariba::rc::Utils;
use ariba::Automation::Constants;
use ariba::Ops::Logger;

my $logger = ariba::Ops::Logger->logger();

my $VERSION = "1.07";

my $DIR = "/home/rc/robotswww/config/published";
my $URL = ariba::Automation::Constants::serverFrontdoor() . "/config/published";

my $SSH = "/usr/local/bin/ssh";
my $WGET = "/usr/bin/wget";

my @PRODUCTS = qw (s4 buyer arches);
my @RELEASES = qw (R4 R3 R2 12s1 12s2 12s1_rel 12s1_limited_hf 12s2_limited_hf 12s2_sp 12s2_rel 13s1 13s2 sproc);

my @ORDER = qw (identity global);

my %INTERESTING =
(
    'identity' => 1,
    'global' => 1,
);

#
# Conveniences
#
sub get_section_order { return @ORDER; }
sub get_releases { return @RELEASES; }
sub get_products { return @PRODUCTS; }
sub get_version { return $VERSION; }

#
# Given CGI parameters, write robot.conf to file + publish to remote machine
#
sub publish_template
{
    my ($params) = @_;

    my (%sections, %etc);

    # break parameters into named sections
    foreach my $key (keys %$params)
    {
        my ($this, $that) = split /\./, $key;
        $this = $this || "";
        $that = $that || "";

        if (exists $INTERESTING{$this})
        {
            $sections{$this}{$that} = $params->{$key};
        }
        else
        {
            $etc{$key} = $params->{$key};
        }
    }

    my $product = $params->{'global.productName'};
    my $release = $params->{'release'} || "";

    # generate branch
    my $branch = $params->{'branch'} ||  "//ariba/ond/" . $product . "/build/" . $release || "//ariba/" . ($product eq "s4" ? "asm" : "buyer") . "/build/" . $release ;

    # unless branch provided by client for sandbox users
    if ($params->{'sandbox_name'})
    {
        $branch = "//ariba/sandbox/build/" . $params->{'sandbox_name'} . "/" . $product;
    }

    # generate robot.conf.local
    my $now = localtime (time());
    my @lines = ("# Generated by: ConfigWriter/$VERSION on $now", "");

    foreach my $i (0 .. $#ORDER)
    {
        my $key = $ORDER[$i];
        foreach my $item (sort keys %{$sections{$key}})
        {
            my $parameter = join ".", $key, $item;
            my $line = join "=", $parameter, $sections{$key}{$item};
            push @lines, $line;
        }
        push @lines, "" unless $i == $#ORDER;
    }

    push @lines, "global.waitTimeInMinutes=5";
    push @lines, "global.emailFrom=devbuild\@ariba.com <$$params{'identity.description'}>";

    if ($params->{'role'} eq "BQ")
    {
        push @lines, "global.datasetType=robot-BQ";
    }
    elsif ($params->{'role'} eq "LQ")
    {
        push @lines, "global.datasetType=LQ";
        push @lines, "global.serviceType=LQ";
    }
    elsif ($params->{'role'} eq "startserver")
    {
        push @lines, "global.datasetType=robot-BQ";
    }

    push @lines, "global.targetBranchname=$branch";

    my $buildNameTemplate = $params->{'global.productName'} . "_" . $params->{'user'} . "-0";
    if ($params->{'role'} eq "LQ")
    {
        $buildNameTemplate = $params->{'global.productName'} . "_" . "LQ" . "_" . $params->{'user'} . "-0";
    }
    push @lines, "global.buildNameTemplate=$buildNameTemplate";


    # add optional schedule
    my $dow = $params->{'dow'} || "--";
    my $hour = $params->{'hour'} || "--";
    if ($dow ne "--" && $hour ne "--")
    {
        $hour =~ s/^0//; # strip leading zero
        push @lines, "global.buildSchedule=$dow\@$hour";
    }

    push @lines, "";

    my $purpose = $params->{'purpose'};
    if ($purpose eq "sandbox")
    {
        $purpose = "mainline";
    }
    if ($purpose eq "sandbox-qual")
    {
        $purpose = "qual";
    }
    if ($params->{'role'} eq "startserver")
    {
        $purpose = "startserver";
    }
    if ($params->{'role'} eq "LQ")
    {
        $purpose = "lq";
    }
    
    # generate build name template
    my $type = $params->{'type'};
    my $templatename = $type eq "migration" ? "mig" : $type;
    my $template = join ".", $params->{'global.productName'}, $templatename, "conf";

    # some LQ robots run against mainline
    if ($params->{'role'} eq "LQ" && ($params->{'purpose'} eq "mainline" || $params->{'purpose'} eq "sandbox"))
    {
        $template = join ".", "mainline", $template;
    }

    push @lines, "#include //ariba/services/tools/robots/config/$purpose/$template";

    # override the branch name in stock template
    if ($params->{'role'} eq "LQ" && $params->{'purpose'} eq "mainline")
    {
        push @lines, "";
        push @lines, "action.10s2-buildname-from-label.branch=$release";
    }
    elsif ($params->{'role'} eq "LQ" && $params->{'purpose'} eq "qual")
    {
        push @lines, "";
        push @lines, "action.hawk-buildname-from-label.branch=$release";
    }
    elsif ($params->{'role'} eq "BQ" && $params->{'purpose'} eq "qual")
    {
        push @lines, "";
        push @lines, "action.hawk-buildname-from-label.branch=$release";
    }
    elsif ($params->{'role'} eq "BQ" && $params->{'purpose'} eq "sandbox-qual")
    {
        push @lines, "";
        push @lines, "action.hawk-buildname-from-label.branch=$params->{'sandbox_name'}";
    }

	# disable e-mail if making a mainline robot
    if ($params->{'purpose'} eq "mainline")
    {
        push @lines, "";
        push @lines, "global.noSpam=1";
    }

    # write lines to tmpfile
    my $host = $params->{'hostname'};

    # check for invalid hostname
    if ($host !~ m#^[A-Z0-9\.]+$#i)
    {
        return 0;
    }

    # check for invalid username
    my $user = $params->{'user'};
    if ($user !~ m#^[A-Z0-9]+$#i)
    {
        return 0;
    }

    my $url = join "/", $URL, "$host.conf";
    my $tmp = join "/", $DIR, "$host.conf";
    my $remote_file = "/tmp/$host.conf";

    if (open FILE, ">$tmp.tmp")
    {
        if (print FILE "" . (join "\n", @lines) . "\n")
        {
            if (close (FILE))
            {
                if (move ("$tmp.tmp", $tmp))
                {
                    if (install_config_file ($host, $user, $user, $remote_file, $url))
                    {
                        cleanup ($tmp);
                        return 1;
                    }
                    else
                    {
                        $logger->warning ("Installing $remote_file via $url to $user\@host failed");
                    }
                }
                else
                {
                    $logger->warning ("Couldn't move $tmp.tmp to $tmp: $!");
                }
            }
            else
            {
                $logger->warning ("Couldn't close file $tmp.tmp: $!");
            }
        }
        else
        {
            $logger->warning ("Failed printing to $tmp.tmp: $!");
        }
    }
    else
    {
        $logger->warning ("Failed writing to $tmp.tmp: $!");
    }

    cleanup ("$tmp.tmp", $tmp);
    return 0;
}

#
# Push file to remote system
#
sub install_config_file
{
    my ($host, $user, $passwd, $remote_file, $url) = @_;

    my $timestamp = POSIX::strftime("%Y%m%d-%H%M%S", localtime);
    my $conf = "~/config/robot.conf.local";

    my @cmds =
    (
        "mkdir -p ~/config",
        "touch $conf",
        "cp $conf /tmp/$timestamp.robot.conf.local",
        "rm -f $remote_file",
        "$WGET -q -O $remote_file $url",
        "mv -f $remote_file $conf",
    );

    my $cmds = join " && ", @cmds;
    print "<p>$cmds</p>";

    my $cmd = qq!$SSH -n $host -l $user "$cmds"!;
    print "<p>$cmd</p>\n";

    return ariba::rc::Utils::executeRemoteCommand ($cmd, $passwd);
}

#
# Remove temporary files
#
sub cleanup
{
    while (my $file = shift)
    {
        if (-e $file)
        {
            unlink $file;
        }
    }
}

#
# Load template by sections
#
sub parse_template
{
    my ($file, $remote_user) = @_;

    $remote_user = $remote_user || "";

    my (%items, %help);
    my $help = "";

    open FILE, $file;

    while (<FILE>)
    {
        chomp;
        next unless length ($_);

        if ($_ =~ m/^# help: (.*)$/)
        {
            $help = $1;
            next;
        }
        elsif (substr ($_, 0, 1) eq '#')
        {
            next;
        }

        my ($this, $that) = split /\./, $_, 2;
        next unless $this;

        if (exists $INTERESTING{$this})
        {
            my ($key, $value) = split /=/, $that, 2;

            # substitute default e-mail address with username if any
            if ($remote_user && $value eq 'you@ariba.com')
            {
                $value = $remote_user . '@ariba.com';
            }

            $items{$this}{$key} = $value;
            if ($help)
            {
                $help{$key} = $help;
            }
            $help = "";
        }
    }

    close FILE;

    return (\%items, \%help);
}

1;
