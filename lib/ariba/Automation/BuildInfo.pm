package ariba::Automation::BuildInfo;

# 
# Class responsible for storing this data:
#
# - Builds (represented by ever-incrementing build number)
# - Test ID#s (generated by qual class)
# - Log Directory + Log Filename
# - CL# start/end range
#
# Provides methods for:
# - Parsing (packing/unpacking) for storage by PersistantObject class
#
# Purpose of class: Abstract the data involved so callers don't have 
# to know about the underlying format. 
# 

use strict 'vars';
use warnings;
use vars qw ($AUTOLOAD);
use Carp;

{
#
# Build Info defaults
#
my %_attr_data =
    (
	  _buildNumber => [ 0, "rw" ],
	  _logDir => [ "", "rw" ],
	  _logFile => [ "", "rw" ],
	  _changeStart => [ 0, "rw" ],
	  _changeEnd => [ 0, "rw" ],
	  _qualTestId => [ 0, "rw" ],
	  _qualStatus => [ 0, "rw" ],
	  _productName => [ "", "rw" ],
	  _productBuildName => [ "", "rw" ],
	  _buildTime => [ 0, "rw" ],
	  _qualTime => [ 0, "rw" ],
    );

#
# Private method to manage attribute access
#
sub _accessible
    {
    my ($self, $attr, $mode) = @_;
    $_attr_data{$attr}[1] =~ /$mode/
    }

#
# Private method to get default for attributes
#
sub _default_for
    {
    my ($self, $attr) = @_;
    $_attr_data{$attr}[0];
    }

#
# Private method gives access to attributes
#
sub _standard_keys
    {
    keys %_attr_data;
    }

#
# Constructor
#
sub new
    {
    my ($caller, %arg) = @_;
    my $caller_is_obj = ref($caller);
    my $class = $caller_is_obj || $caller;
    my $self = bless {}, $class;
    foreach my $membername ( $self->_standard_keys() )
        {
        my ($argname) = ($membername =~ /^_(.*)/);
        if (exists $arg{$argname})
            { $self->{$membername} = $arg{$argname} }
        elsif ($caller_is_obj)
            { $self->{$membername} = $caller->{$membername} }
        else
            { $self->{$membername} = $self->_default_for($membername) }
        }

    return $self;
    }

#
# Parse packed build info into this class
#
sub unpack
	{
	my ($self, $packed) = @_;
	my (@values) = split /:/, $packed;
	$self->set_buildNumber ($values[0]);
	$self->set_logDir ($values[1]);
	$self->set_logFile ($values[2]);
	$self->set_changeStart ($values[3]);
	$self->set_changeEnd ($values[4]);
	$self->set_qualTestId ($values[5]);
	$self->set_qualStatus ($values[6]);
	$self->set_productName ($values[7]);
	$self->set_productBuildName ($values[8]);
	$self->set_buildTime ($values[9]);
	$self->set_qualTime ($values[10]) if defined $values[10];
	}

#
# Take class attributes and present them in packed form
#
sub pack
	{
	my ($self) = @_;
	return join ":", 
		$self->get_buildNumber, 
		$self->get_logDir, 
		$self->get_logFile, 
		$self->get_changeStart, 
		$self->get_changeEnd,
		$self->get_qualTestId,
		$self->get_qualStatus,
		$self->get_productName,
		$self->get_productBuildName,
		$self->get_buildTime, 
		$self->get_qualTime,
	}

#
# Pretty-print build info object contents
#

sub dump
	{
	my ($self) = @_;
	return "Build #" . $self->get_buildNumber() . ": " . 
		"dir=" . $self->get_logDir() . "/" . $self->get_logFile() . " " . 
		"CL=" . $self->get_changeStart() . "-" . $self->get_changeEnd() . " " . 
		"Qual status=" . $self->get_qualStatus() . " testId=" . $self->get_qualTestId() . " " .
		"Start time=" . localtime ($self->get_buildTime()) . " " . 
		"Qual time=" . localtime ($self->get_qualTime()) . " " . 
		"Product name=" . $self->get_productName() . " build=" . $self->get_productBuildName() . "\n";
	}

#
# Auto-generate class accessors
#
sub AUTOLOAD
    {
    no strict "refs";
    my ($self, $newval) = @_;

    # getter
    if ($AUTOLOAD =~ /.*::get(_\w+)/ && $self->_accessible($1,'r'))
        {
        my $attr_name = $1;
        *{$AUTOLOAD} = sub { return $_[0]->{$attr_name} };
        return $self->{$attr_name}
        }

    # setter
    if ($AUTOLOAD =~ /.*::set(_\w+)/ && $self->_accessible($1,'rw'))
        {
        my $attr_name = $1;
        *{$AUTOLOAD} = sub { $_[0]->{$attr_name} = $_[1] };
        $self->{$1} = $newval;
        return
        }

    # complain if we couldn't find a matching method
    carp "no such method: $AUTOLOAD";
    }

#
# Destructor
#
sub DESTROY
    {
    my ($self) = @_;
    }
}

1;
