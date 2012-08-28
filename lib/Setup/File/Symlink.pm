package Setup::File::Symlink;

use 5.010;
use strict;
use warnings;
use Log::Any '$log';

use File::Trash::Undoable;

require Exporter;
our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(setup_symlink);

# VERSION

our %SPEC;

$SPEC{rmsym} = {
    v           => 1.1,
    summary     => 'Delete symlink',
    description => <<'_',

Will not delete non-symlinks.

Fixed state: `path` doesn't exist.

Fixable state: `path` exists, is a symlink, (and if `target` is defined, points
to `target`).

_
    args        => {
        path => {
            schema => 'str*',
        },
        target => {
            summary => 'Only delete if existing symlink has this target',
            schema => 'str*',
        },
    },
    features => {
        tx => {v=>2},
        idempotent => 1,
    },
};
sub rmsym {
    my %args = @_;

    # TMP, schema
    my $tx_action = $args{-tx_action} // '';
    my $path = $args{path};
    defined($path) or return [400, "Please specify path"];
    my $target = $args{target};

    my $is_sym   = (-l $path);
    my $exists   = $is_sym || (-e _);
    my $curtarget; $curtarget = readlink($path) if $is_sym;

    my @undo;

    if ($tx_action eq 'check_state') {
        return [412, "Not a symlink"] if $exists && !$is_sym;
        return [412, "Target does not match ($curtarget)"] if $is_sym &&
            defined($target) && $curtarget ne $target;
        if ($exists) {
            $log->info("nok: Symlink $path should be removed");
            push @undo, ['ln_s', {
                symlink => $path,
                target  => $target // $curtarget,
            }];
        }
        if (@undo) {
            return [200, "Fixable", undef, {undo_actions=>\@undo}];
        } else {
            return [304, "Fixed"];
        }
    } elsif ($tx_action eq 'fix_state') {
        if (unlink $path) {
            return [200, "Fixed"];
        } else {
            return [500, "Can't remove symlink: $!"];
        }
    }
    [400, "Invalid -tx_action"];
}

$SPEC{ln_s} = {
    v           => 1.1,
    summary     => 'Create symlink',
    description => <<'_',

Fixed state: `symlink` exists and points to `target`.

Fixable state: `symlink` doesn't exist.

_
    args        => {
        symlink => {
            summary => 'Path to symlink',
            schema => 'str*',
        },
        target => {
            summary => 'Path to target',
            schema => 'str*',
        },
    },
    features => {
        tx => {v=>2},
        idempotent => 1,
    },
};
sub ln_s {
    my %args = @_;

    # TMP, schema
    my $tx_action = $args{-tx_action} // '';
    my $symlink = $args{symlink};
    defined($symlink) or return [400, "Please specify symlink"];
    my $target = $args{target};
    defined($target) or return [400, "Please specify target"];

    my $is_sym   = (-l $symlink);
    my $exists   = $is_sym || (-e _);
    my $curtarget; $curtarget = readlink($symlink) if $is_sym;
    my @undo;

    if ($tx_action eq 'check_state') {
        return [412, "Path already exists"] if $exists && !$is_sym;
        return [412, "Symlink points to another target"] if $is_sym &&
            $curtarget ne $target;
        if (!$exists) {
            $log->info("nok: Symlink $symlink -> $target should be created");
            push @undo, ['rmsym', {path => $symlink}];
        }
        if (@undo) {
            return [200, "Fixable", undef, {undo_actions=>\@undo}];
        } else {
            return [304, "Fixed"];
        }
    } elsif ($tx_action eq 'fix_state') {
        if (symlink $target, $symlink) {
            return [200, "Fixed"];
        } else {
            return [500, "Can't symlink: $!"];
        }
    }
    [400, "Invalid -tx_action"];
}

$SPEC{setup_symlink} = {
    v           => 1.1,
    summary     => "Setup symlink (existence, target)",
    description => <<'_',

On do, will create symlink which points to specified target. If symlink already
exists but points to another target, it will be replaced with the correct
symlink if `replace_symlink` option is true. If a file/dir already exists and
`replace_file`/`replace_dir` option is true, it will be moved (trashed) first
before the symlink is created.

On undo, will delete symlink if it was created by this function, and restore the
original symlink/file/dir if it was replaced during do.

_
    args        => {
        symlink => {
            summary => 'Path to symlink',
            schema => ['str*' => {match => qr!^/!}],
            req => 1,
            pos => 1,
        },
        target => {
            summary => 'Target path of symlink',
            schema => 'str*',
            req => 1,
            pos => 0,
        },
        create => {
            summary => "Create if symlink doesn't exist",
            schema => [bool => {default=>1}],
            description => <<'_',

If set to false, then setup will fail (412) if this condition is encountered.

_
        },
        replace_symlink => {
            summary => "Replace previous symlink if it already exists ".
                "but doesn't point to the wanted target",
            schema => ['bool' => {default => 1}],
            description => <<'_',

If set to false, then setup will fail (412) if this condition is encountered.

_
        },
        replace_file => {
            summary => "Replace if there is existing non-symlink file",
            schema => ['bool' => {default => 0}],
            description => <<'_',

If set to false, then setup will fail (412) if this condition is encountered.

_
        },
        replace_dir => {
            summary => "Replace if there is existing dir",
            schema => ['bool' => {default => 0}],
            description => <<'_',

If set to false, then setup will fail (412) if this condition is encountered.

_
        },
    },
    features    => {
        tx => {v=>2},
        idempotent => 1,
    },
};
sub setup_symlink {
    my %args = @_;

    # TMP, schema
    my $tx_action    = $args{-tx_action} // '';
    my $symlink      = $args{symlink} or return [400, "Please specify symlink"];
    my $target       = $args{target};
    defined($target) or return [400, "Please specify target"];
    my $create       = $args{create}       // 1;
    my $replace_file = $args{replace_file} // 0;
    my $replace_dir  = $args{replace_dir}  // 0;
    my $replace_symlink = $args{replace_symlink} // 1;

    my $is_symlink = (-l $symlink); # -l performs lstat()
    my $exists     = (-e _);    # now we can use -e
    my $is_dir     = (-d _);
    my $cur_target = $is_symlink ? readlink($symlink) : "";

    my (@do, @undo);

    if ($exists && !$is_symlink) {
        $log->info("nok: ".($is_dir ? "Dir" : "File")." $symlink ".
                       "should be replaced by symlink");
        if ($is_dir && !$replace_dir) {
            return [412, "must replace dir but instructed not to"];
        } elsif (!$is_dir && !$replace_file) {
            return [412, "must replace file but instructed not to"];
        }
        push @do, (
            ["File::Trash::Undoable::trash", {path=>$symlink}],
            ["ln_s", {symlink=>$symlink, target=>$target}],
        );
        push @undo, (
            ["rmsym", {path=>$symlink, target=>$target}],
            ["File::Trash::Undoable::untrash", {path=>$symlink}],
        );
    } elsif ($is_symlink && $cur_target ne $target) {
        $log->infof("nok: Symlink $symlink doesn't point to correct target".
                        " $target");
        if (!$replace_symlink) {
            return [412, "must replace symlink but instructed not to"];
        }
        push @do, (
            [rmsym => {path=>$symlink}],
            [ln_s  => {symlink=>$symlink, target=>$target}],
        );
        push @undo, (
            ["rmsym", {path=>$symlink, target=>$target}],
            ["ln_s", {symlink=>$symlink, target=>$cur_target}],
        );
    } elsif (!$exists) {
        $log->infof("nok: $symlink doesn't exist");
        if (!$create) {
            return [412, "must create symlink but instructed not to"];
        }
        push @do, (
            ["ln_s", {symlink=>$symlink, target=>$target}],
        );
        push @undo, (
            ["rmsym", {path=>$symlink}],
        );
    }

    if (@do) {
        return [200,"Fixable",undef, {do_actions=>\@do, undo_actions=>\@undo}];
    } else {
        return [304, "Fixed"];
    }
}

1;
# ABSTRACT: Setup symlink (existence, target)

=head1 SEE ALSO

L<Setup>

L<Setup::File>

=cut
