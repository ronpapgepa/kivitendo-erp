package SL::BackgroundJob::ShopPartMassUpload;
#ShopPartMassUpload
use strict;
use warnings;

use parent qw(SL::BackgroundJob::Base);

use SL::DBUtils;
use SL::DB::ShopPart;
      use SL::Shop;

use constant WAITING_FOR_EXECUTION        => 0;
use constant UPLOAD_TO_WEBSHOP            => 1;
use constant DONE                         => 2;

# Data format:
# my $data                  = {
#     shop_part_record_ids       => [ 603, 604, 605],
#     num_order_created           => 0,
#     orders_ids                  => [1,2,3]
#     conversation_errors         => [ { id => 603 , item => 2, message => "Out of stock"}, ],
# };

sub update_webarticles {
  my ( $self ) = @_;

  my $job_obj = $self->{job_obj};
  my $db      = $job_obj->db;

  $job_obj->set_data(UPLOAD_TO_WEBSHOP())->save;

  foreach my $shop_part_id (@{ $job_obj->data_as_hash->{shop_part_record_ids} }) {
    my $data  = $job_obj->data_as_hash;
    eval {
      my $shop_part = SL::DB::Manager::ShopPart->find_by(id => $shop_part_id);
      unless($shop_part){
        push @{ $data->{conversion_errors} }, { id => $shop_part_id, number => '', message => 'Shoppart not found' };
      }

      my $shop = SL::Shop->new( config => $shop_part->shop );

      my $part_hash = $shop_part->part->as_tree;
      require SL::JSON;

      my $json      = SL::JSON::to_json($part_hash);
      my $return    = $shop->connector->update_part($shop_part, $json, $data->{todo});
      if ( $return == 1 ) {
        my $now = DateTime->now;
        my $attributes->{last_update} = $now;
        $shop_part->assign_attributes(%{ $attributes });
        $shop_part->save;
      }else{
      push @{ $data->{conversion_errors} }, { id => $shop_part_id, number => '', message => $return };
      }
      1;
    } or do {
      push @{ $data->{conversion_errors} }, { id => $shop_part_id, number => '', message => $@ };
    };

    $job_obj->update_attributes(data_as_hash => $data);
  }
}

sub run {
  my ($self, $job_obj) = @_;

  $self->{job_obj}         = $job_obj;
  $self->update_webarticles;

  $job_obj->set_data(status => DONE())->save;

  return 1;
}
1;
