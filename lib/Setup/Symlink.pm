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
    my %args        = @_;
    my $dry_run     = $args{-dry_run};
    my $undo_action = $args{-undo_action};

    # check args
    my $symlink     = $args{symlink};
    $symlink =~ m!^/!
        or return [400, "Please specify an absolute path for symlink"];
    my $target  = $args{target};
    defined($target) or return [400, "Please specify target"];
    my $create      = $args{create} // 1;
    my $delete_file = $args{delete_dir} // 0;
    my $delete_dir  = $args{delete_file} // 0;
    my $replace     = $args{replace_symlink} // 1;

    # check current state
    my $is_symlink = (-l $symlink); # -l performs lstat()
    my $exists     = (-e _);        # now we can use -e
    my $is_dir     = (-d _);
    my $cur_target = $is_symlink ? readlink($symlink) : "";
    my $state_ok   = $is_symlink && $cur_target eq $target;

    if ($undo_action eq 'undo') {
        return [412, "Can't undo: currently $symlink is not a symlink ".
                    "pointing to $target"] unless $state_ok;
        unlink $symlink or return [500, "Can't undo: can't rm $symlink: $!"];
        my $undo_info = $args{-undo_info};
        if ($undo_info->[0] eq 'dir') {
            # XXX mv $undo_info->[1], $symlink;
        } elsif ($undo_info->[0] eq 'file') {
            # XXX mv $undo_info->[1], $symlink;
        } elsif ($undo_info->[0] eq 'none') {
        } else {
            return [412, "Invalid undo info"];
        }
        return [200, "OK", undef, {}];
    }

    my $undo_hint = $args{-undo_hint};

    # XXX perform action, save undo info

}

1;
__END__

=head1 SYNOPSIS

 use Setup::Symlink 'setup_symlink';

 # simple usage (doesn't save undo info)
 my $res = setup_symlink symlink => "/baz", target => "/qux";
 die unless $res->[0] == 200;

 # save undo info
 my $res = setup_symlink symlink => "/foo", target => "/bar",
                         -undo_action => 'do';
 die unless $res->[0] == 200;
 my $undo_info = $res->[3]{undo_info};

 # perform undo
 my $res = setup_symlink symlink => "/symlink", target=>"/target",
                         -undo_action => "undo", -undo_info=>$undo_info;
 die unless $res->[0] == 200;

=head1 DESCRIPTION

This module provides one function B<setup_symlink> to setup symlinks.

I use the C<Setup::> namespace for modules that contain functions to set things
up, that is, to reach some desired state (for example, making sure some
file/symlink exists with the right content/permission/target). The functions
should do nothing if that desired state has already been reached. They should
also be able to restore state (undo) to original state.

This module uses L<Log::Any> logging framework.

This module's functions have L<Sub::Spec> specs.


=head1 FUNCTIONS

None are exported by default, but they are exportable.


=head1 SEE ALSO

L<Sub::Spec>

L<Sub::Spec::Runner>

=cut
