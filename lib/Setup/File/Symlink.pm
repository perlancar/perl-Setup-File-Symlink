package Setup::File::Symlink;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;
use Log::Any::IfLOG '$log';

use File::Trash::Undoable;

require Exporter;
our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(setup_symlink);

our %SPEC;

$SPEC{':package'} = {
    v => 1.1,
    summary => 'Setup symlink (existence, target)',
};

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
    my $dry_run   = $args{-dry_run};
    my $path      = $args{path};
    defined($path) or return [400, "Please specify path"];
    my $target    = $args{target};

    my $is_sym    = (-l $path);
    my $exists    = $is_sym || (-e _);
    my $curtarget; $curtarget = readlink($path) if $is_sym;

    my @undo;

    if ($tx_action eq 'check_state') {
        return [412, "$path is not a symlink"] if $exists && !$is_sym;
        return [412, "Target of symlink $path does not match ($curtarget)"]
            if $is_sym && defined($target) && $curtarget ne $target;
        if ($exists) {
            unshift @undo, ['ln_s', {
                symlink => $path,
                target  => $target // $curtarget,
            }];
        }
        if (@undo) {
            $log->info("(DRY) Deleting symlink $path ...") if $dry_run;
            return [200, "Symlink $path should be removed", undef,
                    {undo_actions=>\@undo}];
        } else {
            return [304, "Symlink $path already does not exist"];
        }
    } elsif ($tx_action eq 'fix_state') {
        $log->info("Deleting symlink $path ...");
        if (unlink $path) {
            return [200, "OK"];
        } else {
            return [500, "Can't remove symlink $path: $!"];
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
    my $dry_run   = $args{-dry_run};
    my $symlink   = $args{symlink};
    defined($symlink) or return [400, "Please specify symlink"];
    my $target    = $args{target};
    defined($target) or return [400, "Please specify target"];

    my $is_sym    = (-l $symlink);
    my $exists    = $is_sym || (-e _);
    my $curtarget; $curtarget = readlink($symlink) if $is_sym;
    my @undo;

    if ($tx_action eq 'check_state') {
        return [412, "Path $symlink already exists"] if $exists && !$is_sym;
        return [412, "Symlink $symlink points to another target"] if $is_sym &&
            $curtarget ne $target;
        if (!$exists) {
            unshift @undo, ['rmsym', {path => $symlink}];
        }
        if (@undo) {
        $log->info("(DRY) Creating symlink $symlink -> $target ...")
            if $dry_run;
        return [200, "Symlink $symlink needs to be created", undef,
                {undo_actions=>\@undo}];
        } else {
            return [304, "Symlink $symlink already exists"];
        }
    } elsif ($tx_action eq 'fix_state') {
        $log->info("Creating symlink $symlink -> $target ...");
        if (symlink $target, $symlink) {
            return [200, "Fixed"];
        } else {
            return [500, "Can't symlink $symlink -> $target: $!"];
        }
    }
    [400, "Invalid -tx_action"];
}

$SPEC{setup_symlink} = {
    v           => 1.1,
    summary     => "Setup symlink (existence, target)",
    description => <<'_',

When `should_exist=>1` (the default): On do, will create symlink which points to
specified target. If symlink already exists but points to another target, it
will be replaced with the correct symlink if `replace_symlink` option is true.
If a file/dir already exists and `replace_file`/`replace_dir` option is true, it
will be moved (trashed) first before the symlink is created. On undo, will
delete symlink if it was created by this function, and restore the original
symlink/file/dir if it was replaced during do.

When `should_exist=>0`: On do, will remove symlink if it exists (and
`replace_symlink` is true). If `replace_file`/`replace_dir` is true, will also
remove file/dir. On undo, will restore deleted symlink/file/dir.

_
    args        => {
        should_exist => {
            summary => "Whether symlink should exist",
            schema => ['bool' => {default => 1}],
        },
        symlink => {
            summary => 'Path to symlink',
            schema => ['str*' => {match => qr!^/!}],
            req => 1,
            pos => 0,
        },
        target => {
            summary => 'Target path of symlink',
            schema => 'str*',
            req => 0, # XXX only when should_exist=1
            description => <<'_',

Required, unless `should_exist => 0`.

_
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
    require UUID::Random;

    my %args = @_;

    # TMP, schema
    my $tx_action    = $args{-tx_action} // '';
    my $dry_run      = $args{-dry_run};
    my $should_exist = $args{should_exist} // 1;
    my $symlink      = $args{symlink} or return [400, "Please specify symlink"];
    my $target       = $args{target};
    if ($should_exist) {
        defined($target) or return [400, "Please specify target"];
    }
    my $create          = $args{create}       // 1;
    my $replace_file    = $args{replace_file} // 0;
    my $replace_dir     = $args{replace_dir}  // 0;
    my $replace_symlink = $args{replace_symlink} // 1;

    my $is_sym     = (-l $symlink); # -l performs lstat()
    my $exists     = (-e _);    # now we can use -e
    my $is_dir     = (-d _);
    my $cur_target = $is_sym ? readlink($symlink) : "";

    my $taid       = $args{-tx_action_id} // UUID::Random::generate();
    my $suffix     = substr($taid,0,8);

    my (@do, @undo);

    if ($should_exist) {
        if ($exists && !$is_sym) {
            if ($is_dir && !$replace_dir) {
                return [412, "Must replace dir $symlink with symlink ".
                            "but instructed not to"];
            } elsif (!$is_dir && !$replace_file) {
                return [412, "Must replace file $symlink with symlink ".
                            "but instructed not to"];
            }
            $log->info("(DRY) Replacing file/dir $symlink with symlink ...")
                if $dry_run;
            push @do, (
                ["File::Trash::Undoable::trash",
                 {path=>$symlink, suffix=>$suffix}],
                ["ln_s", {symlink=>$symlink, target=>$target}],
            );
            unshift @undo, (
                ["rmsym", {path=>$symlink, target=>$target}],
                ["File::Trash::Undoable::untrash",
                 {path=>$symlink, suffix=>$suffix}],
            );
        } elsif ($is_sym && $cur_target ne $target) {
            if (!$replace_symlink) {
                return [412, "Must replace symlink $symlink ".
                            "but instructed not to"];
            }
            $log->info("(DRY) Replacing symlink $symlink ...") if $dry_run;
            push @do, (
                [rmsym => {path=>$symlink}],
                [ln_s  => {symlink=>$symlink, target=>$target}],
            );
            unshift @undo, (
                ["rmsym", {path=>$symlink, target=>$target}],
                ["ln_s", {symlink=>$symlink, target=>$cur_target}],
            );
        } elsif (!$exists) {
            if (!$create) {
                return [412, "Must create symlink $symlink ".
                            "but instructed not to"];
            }
            $log->info("(DRY) Creating symlink $symlink ...") if $dry_run;
            push @do, (
                ["ln_s", {symlink=>$symlink, target=>$target}],
            );
            unshift @undo, (
                ["rmsym", {path=>$symlink}],
            );
        }
    } elsif ($exists) {
        return [412, "Must delete symlink $symlink but instructed not to"]
            if $is_sym && !$replace_symlink;
        return [412, "Must delete dir $symlink but instructed not to"]
            if $is_dir && !$replace_dir;
        return [412, "Must delete file $symlink but instructed not to"]
            if !$is_sym && !$is_dir && !$replace_file;
        $log->info("(DRY) Removing symlink $symlink ...") if $dry_run;
        push    @do  , ["File::Trash::Undoable::trash",
                        {path=>$symlink, suffix=>$suffix}];
        unshift @undo, ["File::Trash::Undoable::untrash",
                        {path=>$symlink, suffix=>$suffix}];
    }

    if (@do) {
        return [200, "", undef, {do_actions=>\@do, undo_actions=>\@undo}];
    } else {
        return [304, "Already fixed"];
    }
}

1;
# ABSTRACT:

=head1 SEE ALSO

L<Setup>

L<Setup::File>

=cut
