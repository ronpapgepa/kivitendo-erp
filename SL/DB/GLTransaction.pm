package SL::DB::GLTransaction;

use strict;

use SL::DB::MetaSetup::GLTransaction;
use SL::Locale::String qw(t8);
use List::Util qw(sum);
use SL::Presenter::GLTransaction;

# Creates get_all, get_all_count, get_all_iterator, delete_all and update_all.
__PACKAGE__->meta->make_manager_class;

__PACKAGE__->meta->add_relationship(
  transactions   => {
    type         => 'one to many',
    class        => 'SL::DB::AccTransaction',
    column_map   => { id => 'trans_id' },
    manager_args => {
      with_objects => [ 'chart' ],
      sort_by      => 'acc_trans_id ASC',
    },
  },
);

__PACKAGE__->meta->initialize;

sub invnumber {
  goto &reference;
}

sub abbreviation     { $_[0]->presenter->abbreviation }
sub displayable_type { $_[0]->presenter->type         }
sub link             { $_[0]->presenter->link_tag     }
sub oneline_summary  { $_[0]->presenter->gist         }

1;
