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
            summary => 'Path to symlink, must be absolute',
            match   => qr!^/!,
        }],
        target => ['str*' => {
            summary => 'Target path of symlink',
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
 setup_symlink symlink => "/symlink", target => "/target";

 # but run through a runner like Sub::Spec::Runner for proper undo action


=head1 DESCRIPTION

This module uses L<Log::Any> logging framework.

This module's functions are given L<Sub::Spec> specs.

=cut
