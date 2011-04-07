package Setup::Symlink;
# ABSTRACT: Setup symlink

use 5.010;
use strict;
use warnings;
use Log::Any '$log';

require Exporter;
our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(setup_symlink);

our %SPEC;

$SPEC{setup_symlink} = {
    summary  => "Create symlink or fix symlink target",
    args     => {
        symlink => ['str*' => {
            summary => 'Path to symlink',
            description => <<'_',

Symlink path needs to be absolute because it is used as a key for states. The
function cannot normalize a non-absolute symlink using something Cwd's abs_path
because that requires the symlink to exist first.

_
            match   => qr!^/!,
        }],
        target => ['str*' => {
            summary => 'Target path of symlink',
        }],
        create => ['bool' => {
            summary => "Create if symlink doesn't exist",
            default => 1,
            description => <<'_',
If set to false, then setup will fail (500) if this condition is encountered.
_
        }],
        replace_symlink => ['bool' => {
            summary => "Replace previous symlink if it already exists ".
                "but doesn't point to the wanted target",
            description => <<'_',
If set to false, then setup will fail (500) if this condition is encountered.
_
            default => 1,
        }],
        delete_file => ['bool' => {
            summary => "Create if previous symlink already exists ".
                "but is not a symlink (a file)",
            description => <<'_',
If set to false, then setup will fail (500) if this condition is encountered.
_
            default => 0,
        }],
        delete_dir => ['bool' => {
            summary => "Create if previous symlink already exists ".
                "but is not a symlink (a dir)",
            description => <<'_',
If set to false, then setup will fail (500) if this condition is encountered.
_
            default => 0,
        }],
    },
    features => {undo=>1, dry_run=>1},
};
sub setup_symlink {
    my %args    = @_;
    my $dry_run = $args{-dry_run};
    my $undo    = $args{-undo};
    my $state   = $args{-state};

    my $symlink = $args{symlink};
    $symlink =~ m!^/!
        or return [400, "Please specify an absolute path for symlink"];
    my $target  = $args{target};

    my ($ok, $nok_msg, $bail);
    my $is_symlink = (-l $symlink); # -l performs lstat()
    my $exists     = (-e _);        # now we can use -e
    my $curtarget  = $is_symlink ? readlink($symlink) : "";
    if ($undo) {
        my $st = $state->get($symlink);
        $ok = !$st || !$exists || !$is_symlink || $curtarget ne $st->{target};
        $nok_msg = "Symlink $symlink exists and was created by us" if !$ok;
    } else {
        if (!$exists) {
            $ok = 0;
            $nok_msg = "Symlink $symlink doesn't exist";
        } elsif (!$is_symlink) {
            $ok = 0;
            $nok_msg = "$symlink is not a symlink";
            $bail++; # bail out, we won't fix this, dangerous
        } elsif ($curtarget ne $target) {
            $ok = 0;
            $nok_msg = "$symlink points to $curtarget instead of $target";
        } else {
            $ok = 1;
        }
    }

    return [304, "OK"] if $ok;
    return [412, $nok_msg] if $dry_run || $bail;

    use autodie;
    if ($undo) {
        $log->debug("deleting symlink $symlink");
        unlink $symlink;
        $state->delete($symlink);
    } else {
        $log->debugf("creating symlink %s -> %s", $symlink, $target);
        unlink $symlink if $exists; # to delete already-created symlink
        symlink $target, $symlink;
        $state->set($symlink => {target=>$target});
    }
    [200, "Fixed"];
}

1;
__END__

=head1 SYNOPSIS

 use Setup::Symlink 'setup_symlink';

 # setup symlink: will create /foo as a symlink to /bar
 setup_symlink symlink => "/foo", target => "/bar", -undo => ;

 # setup another symlink (doesn't save undo info)
 setup_symlink symlink => "/baz", target => "/qux";

 # unsetup symlink: will delete /foo if it's a symlink to /bar
 setup_symlink symlink => "/symlink", target=>"/target", -undo => 1;


=head1 DESCRIPTION

This module provides one function B<setup_symlink> to setup symlinks.

I use the C<Setup::> namespace for modules that contain functions to set things
up, that is, reach some desired state (e.g. some file/symlink exists with the
right content/permission/target), do nothing if that desired state has already
been reached, and additionally can restore state to previous one before changed
by said functions.

This module uses L<Log::Any> logging framework.

This module's functions have L<Sub::Spec> specs.


=head1 FUNCTIONS

None are exported by default, but they are exportable.


=head1 SEE ALSO

L<Sub::Spec>

L<Sub::Spec::Runner>

=cut
