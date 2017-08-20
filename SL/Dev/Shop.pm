package SL::Dev::Shop;

use strict;
use base qw(Exporter);
our @EXPORT = qw(create_shop create_shop_part create_shop_order);

use SL::DB::Shop;

sub create_shop {
  my (%params) = @_;

  my $shop = SL::DB::Shop->new(
    description => 'testshop',
    %params
  );
  return $shop;
}

sub create_shop_part {
  my (%params) = @_;

  my $part = delete $params{part};
  my $shop = delete $params{shop};

  my $shop_part = SL::DB::ShopPart->new(
    part => $part,
    shop => $shop,
    %params
  )->save;
  return $shop_part;
}

sub create_shop_order {
  my (%params) = @_;

  my $shop_order = SL::DB::ShopOrder->new(
    shop => $params{shop},
    %params
  );
  return $shop_order;
}


1;

__END__

=head1 NAME

SL::Dev::Shop - create shop objects for testing, with minimal defaults

=head1 FUNCTIONS

=head2 C<create_shop %PARAMS>

Creates a new shop object.

  my $shop = SL::Dev::Shop::create_shop();

Add a part as a shop part to the shop:

  my $part = SL::Dev::Part::create_part();
  $shop->add_shop_parts( SL::DB::ShopPart->new(part => $part, shop_description => 'Simply the best part!' ) );
  $shop->save;


=head1 BUGS

Nothing here yet.

=head1 AUTHOR

G. Richardson E<lt>grichardson@kivitendo-premium.deE<gt>

=cut
