package SL::ShopConnector::Shopware;

use strict;

use parent qw(SL::ShopConnector::Base);

use SL::DBUtils;
use SL::JSON;
use LWP::UserAgent;
use LWP::Authen::Digest;
use SL::DB::ShopOrder;
use SL::DB::ShopOrderItem;
use SL::DB::History;
use DateTime::Format::Strptime;
use SL::DB::File;
use Data::Dumper;
use Sort::Naturally ();
use SL::Helper::Flash;
use Encode qw(encode_utf8);
use SL::File;
use File::Slurp;

use Rose::Object::MakeMethods::Generic (
  'scalar --get_set_init' => [ qw(connector url) ],
);

sub get_order_max {
  my ($self) = @_;
  my %params = ( sort  => { property  => 'number',
                            direction => 'DESC',
                          },
               );
  my $url       = $self->url;
  my $data      = $self->connector->get($url . "api/orders?limit=1", %params);
  my $data_json = $data->content;
  my $import    = SL::JSON::decode_json($data_json);
}

sub get_new_orders {
  my ($self, $id) = @_;

  my $url       = $self->url;
  my $ordnumber = $self->config->last_order_number + 1;
  my $otf       = $self->config->orders_to_fetch;
  my $of        = 0;
    my %params = ( filter => [  property   => 'customerId',
                                  value      => 1,

                             ],
                 );
    my @filter = (  { property   => 'customerId',
                        value      => 1,
                      }

                 );
                 %params = ( filter => [ @filter ]);
    my $orders_data      = $self->connector->get($url . "api/orders?limit=$otf&filter[0][property]=number&filter[0][expression]=>&filter[0][value]=" . $self->config->last_order_number);
    my $orders_data_json = $orders_data->content;
    my $orders_import    = SL::JSON::decode_json($orders_data_json);

    if ($orders_import->{success}){
      foreach my $shoporder(@{ $orders_import->{data} }){

        my $data      = $self->connector->get($url . "api/orders/" . $shoporder->{id});
        my $data_json = $data->content;
        my $import    = SL::JSON::decode_json($data_json);

      my $shop_order = $self->map_data_to_shoporder($import);

      $shop_order->save;
      $of ++;
      my $id = $shop_order->id;

      my @positions = sort { Sort::Naturally::ncmp($a->{"partnumber"}, $b->{"partnumber"}) } @{ $import->{data}->{details} };
      my $position = 1;
      foreach my $pos(@positions) {
        my $price = $::form->round_amount($pos->{price},2);

        my %pos_columns = ( description          => $pos->{articleName},
                            partnumber           => $pos->{articleNumber},
                            price                => $price,
                            quantity             => $pos->{quantity},
                            position             => $position,
                            tax_rate             => $pos->{taxRate},
                            shop_trans_id        => $pos->{articleId},
                            shop_order_id        => $id,
                            active_price_source  => $self->config->price_source,
                          );
        my $pos_insert = SL::DB::ShopOrderItem->new(%pos_columns);
        $pos_insert->save;
        $position++;
      }
      $shop_order->{positions} = $position-1;
      my $customer = $shop_order->get_customer;
      if(ref($customer)){
        $shop_order->kivi_customer_id($customer->id);
        $shop_order->save;
      }

      my $attributes->{last_order_number} = $ordnumber;
      $self->config->assign_attributes( %{ $attributes } );
      $self->config->save;
      $ordnumber++;
    }
  }
  my $shop           = $self->config->description;
  my %fetched_orders = (shop_id => $self->config->id, number_of_orders => $of);
  return \%fetched_orders;
}

sub map_data_to_shoporder {
  my ($self, $import) = @_;
  my $parser = DateTime::Format::Strptime->new( pattern   => '%Y-%m-%dT%H:%M:%S',
                                                  locale    => 'de_DE',
                                                  time_zone => 'local'
                                                );
  my $orderdate = $parser->parse_datetime($import->{data}->{orderTime});
  # Mapping to table shoporders. See http://community.shopware.com/_detail_1690.html#GET_.28Liste.29
  my %columns = (
    amount                  => $import->{data}->{invoiceAmount},
    billing_city            => $import->{data}->{billing}->{city},
    billing_company         => $import->{data}->{billing}->{company},
    billing_country         => $import->{data}->{billing}->{country}->{name},
    billing_department      => $import->{data}->{billing}->{department},
    billing_email           => $import->{data}->{customer}->{email},
    billing_fax             => $import->{data}->{billing}->{fax},
    billing_firstname       => $import->{data}->{billing}->{firstName},
    #billing_greeting        => ($import->{data}->{billing}->{salutation} eq 'mr' ? 'Herr' : 'Frau'),
    billing_lastname        => $import->{data}->{billing}->{lastName},
    billing_phone           => $import->{data}->{billing}->{phone},
    billing_street          => $import->{data}->{billing}->{street},
    billing_vat             => $import->{data}->{billing}->{vatId},
    billing_zipcode         => $import->{data}->{billing}->{zipCode},
    customer_city           => $import->{data}->{billing}->{city},
    customer_company        => $import->{data}->{billing}->{company},
    customer_country        => $import->{data}->{billing}->{country}->{name},
    customer_department     => $import->{data}->{billing}->{department},
    customer_email          => $import->{data}->{customer}->{email},
    customer_fax            => $import->{data}->{billing}->{fax},
    customer_firstname      => $import->{data}->{billing}->{firstName},
    #customer_greeting       => ($import->{data}->{billing}->{salutation} eq 'mr' ? 'Herr' : 'Frau'),
    customer_lastname       => $import->{data}->{billing}->{lastName},
    customer_phone          => $import->{data}->{billing}->{phone},
    customer_street         => $import->{data}->{billing}->{street},
    customer_vat            => $import->{data}->{billing}->{vatId},
    customer_zipcode        => $import->{data}->{billing}->{zipCode},
    customer_newsletter     => $import->{data}->{customer}->{newsletter},
    delivery_city           => $import->{data}->{shipping}->{city},
    delivery_company        => $import->{data}->{shipping}->{company},
    delivery_country        => $import->{data}->{shipping}->{country}->{name},
    delivery_department     => $import->{data}->{shipping}->{department},
    delivery_email          => "",
    delivery_fax            => $import->{data}->{shipping}->{fax},
    delivery_firstname      => $import->{data}->{shipping}->{firstName},
    #delivery_greeting       => ($import->{data}->{shipping}->{salutation} eq 'mr' ? 'Herr' : 'Frau'),
    delivery_lastname       => $import->{data}->{shipping}->{lastName},
    delivery_phone          => $import->{data}->{shipping}->{phone},
    delivery_street         => $import->{data}->{shipping}->{street},
    delivery_vat            => $import->{data}->{shipping}->{vatId},
    delivery_zipcode        => $import->{data}->{shipping}->{zipCode},
    host                    => $import->{data}->{shop}->{hosts},
    netamount               => $import->{data}->{invoiceAmountNet},
    order_date              => $orderdate,
    payment_description     => $import->{data}->{payment}->{description},
    payment_id              => $import->{data}->{paymentId},
    remote_ip               => $import->{data}->{remoteAddress},
    sepa_account_holder     => $import->{data}->{paymentIntances}->{accountHolder},
    sepa_bic                => $import->{data}->{paymentIntances}->{bic},
    sepa_iban               => $import->{data}->{paymentIntances}->{iban},
    shipping_costs          => $import->{data}->{invoiceShipping},
    shipping_costs_net      => $import->{data}->{invoiceShippingNet},
    shop_c_billing_id       => $import->{data}->{billing}->{customerId},
    shop_c_billing_number   => $import->{data}->{billing}->{number},
    shop_c_delivery_id      => $import->{data}->{shipping}->{id},
    shop_customer_id        => $import->{data}->{customerId},
    shop_customer_number    => $import->{data}->{billing}->{number},
    shop_customer_comment   => $import->{data}->{customerComment},
    shop_id                 => $self->config->id,
    shop_ordernumber        => $import->{data}->{number},
    shop_trans_id           => $import->{data}->{id},
    tax_included            => $self->config->pricetype eq "brutto" ? 1 : 0,
  );
  my $shop_order = SL::DB::ShopOrder->new(%columns);
  return $shop_order;
}

sub get_categories {
  my ($self) = @_;

  my $url        = $self->url;
  my $data       = $self->connector->get($url . "api/categories");
  my $data_json  = $data->content;
  my $import     = SL::JSON::decode_json($data_json);
  my @daten      = @{$import->{data}};
  my %categories = map { ($_->{id} => $_) } @daten;

  for(@daten) {
    my $parent = $categories{$_->{parentId}};
    $parent->{children} ||= [];
    push @{$parent->{children}},$_;
  }

  return \@daten;
}

sub get_version {
  my ($self) = @_;

  my $url       = $self->url;
  my $data      = $self->connector->get($url . "api/version");
  my $type = $data->content_type;
  my $status_line = $data->status_line;

  if($data->is_success && $type eq 'application/json'){
    my $data_json = $data->content;
    return SL::JSON::decode_json($data_json);
  }else{
    my %return = ( success => 0,
                   data    => { version => $url . ": " . $status_line, revision => $type },
                   message => "Server not found or wrong data type",
                );
    return \%return;
  }
}

sub get_articles {
  my ($self, $json_data) = @_;

}

sub update_part {
  my ($self, $shop_part, $json, $todo) = @_;

  #shop_part is passed as a param
  die unless ref($shop_part) eq 'SL::DB::ShopPart';

  my $url = $self->url;
  my $part = SL::DB::Part->new(id => $shop_part->{part_id})->load;

  # TODO: Prices (pricerules, pricegroups, multiple prices)
  my $cvars = { map { ($_->config->name => { value => $_->value_as_text, is_valid => $_->is_valid }) } @{ $part->cvars_by_config } };

  my @cat = ();
  foreach my $row_cat ( @{ $shop_part->shop_category } ) {
    my $temp = { ( id => @{$row_cat}[0], ) };
    push ( @cat, $temp );
  }

  my $images = SL::DB::Manager::ShopImage->get_all( where => [ 'files.object_id' => $part->{id}, ], with_objects => 'file', sort_by => 'position' );
  my @upload_img = ();
  foreach my $img (@{ $images }) {
    my $file               = SL::File->get(id => $img->file->id );
    my ($path, $extension) = (split /\./, $file->file_name);
    my $content            = File::Slurp::read_file($file->get_file);
    my $temp ={ ( link        => 'data:' . $file->mime_type . ';base64,' . MIME::Base64::encode($content, ""), #$content, # MIME::Base64::encode($content),
                  description => $img->file->title,
                  position    => $img->position,
                  extension   => $extension,
                  path        => $path,
                      )}    ;
    push( @upload_img, $temp);
  }

  my ($import,$data,$data_json);
#  if( $shop_part->last_update){
    my $partnumber = $::form->escape($part->{partnumber});#shopware don't accept / in articlenumber
# Shopware RestApi schreibt Fehleremail wenn Artikel nicht gefunden. es braucht aber irgendeine Abfrage, ob der Artikel schon im Shop ist.
# LWP->post = neuanlegen LWP->put = update
    $data       = $self->connector->get($url . "api/articles/$partnumber?useNumberAsId=true");
    $data_json  = $data->content;
    $import     = SL::JSON::decode_json($data_json);
#  }

  # get the right price
  # TODO In extra Helper??
  my ( $price_src_str, $price_src_id ) = split(/\//,$shop_part->active_price_source);
  require SL::DB::Part;
  my $price;
  if ($price_src_str eq "master_data") {
    my $part = SL::DB::Manager::Part->get_all( where => [id => $shop_part->part_id], with_objects => ['prices'],limit => 1)->[0];
    $price = $part->$price_src_id;
  }else{
    my $part = SL::DB::Manager::Part->get_all( where => [id => $shop_part->part_id, 'prices.'.pricegroup_id => $price_src_id], with_objects => ['prices'],limit => 1)->[0];
    $price =  $part->prices->[0]->price;
  }

  # get the right taxrate for the article
  # TODO In extra Helper??
  my $taxrate;
  my $dbh  = $::form->get_standard_dbh();
  my $b_id = $part->buchungsgruppen_id;
  my $t_id = $shop_part->shop->taxzone_id;

  my $sql_str = "SELECT a.rate AS taxrate from tax a
  WHERE a.taxkey = (SELECT b.taxkey_id
  FROM chart b LEFT JOIN taxzone_charts c ON b.id = c.income_accno_id
  WHERE c.taxzone_id = $t_id
  AND c.buchungsgruppen_id = $b_id)";

  my $rate = selectall_hashref_query($::form, $dbh, $sql_str);
  $taxrate = @$rate[0]->{taxrate}*100;

  # mapping to shopware still missing attributes,metatags
  my %shop_data;

  if($todo eq "price"){
    %shop_data = ( mainDetail => { number   => $part->{partnumber},
                                   prices   =>  [ { from             => 1,
                                                    price            => $price,
                                                    customerGroupKey => 'EK',
                                                  },
                                                ],
                                  },
                 );
  }elsif($todo eq "stock"){
    %shop_data = ( mainDetail => { number   => $part->{partnumber},
                                   inStock  => $part->{onhand},
                                 },
                 );
  }elsif($todo eq "price_stock"){
    %shop_data =  ( mainDetail => { number   => $part->{partnumber},
                                    inStock  => $part->{onhand},
                                    prices   =>  [ { from             => 1,
                                                     price            => $price,
                                                     customerGroupKey => 'EK',
                                                   },
                                                 ],
                                   },
                   );
  }elsif($todo eq "active"){
    %shop_data =  ( mainDetail => { number   => $part->{partnumber},
                                   },
                    active => ($part->{partnumber} == 1 ? 0 : 1),
                   );
  }elsif($todo eq "all"){
  # mapping to shopware still missing attributes,metatags
    %shop_data =  (   name              => $part->{description},
                      mainDetail        => { number   => $part->{partnumber},
                                             inStock  => $part->{onhand},
                                             prices   =>  [ {          from   => 1,
                                                                       price  => $price,
                                                            customerGroupKey  => 'EK',
                                                            },
                                                          ],
                                             #attribute => { attr1  => $cvars->{CVARNAME}->{value}, } , #HowTo handle attributes
                                       },
                      supplier          => 'AR', # Is needed by shopware,
                      descriptionLong   => $shop_part->{shop_description},
                      active            => $shop_part->active,
                      images            => [ @upload_img ],
                      __options_images  => { replace => 1, },
                      categories        => [ @cat ],
                      description       => $shop_part->{shop_description},
                      categories        => [ @cat ],
                      tax               => $taxrate,
                    )
                  ;
  }

  my $dataString = SL::JSON::to_json(\%shop_data);
  $dataString    = encode_utf8($dataString);

  my $upload_content;
  my $upload;
  if($import->{success}){
    #update
    my $partnumber  = $::form->escape($part->{partnumber});#shopware don't accept / in articlenumber
    $upload         = $self->connector->put($url . "api/articles/$partnumber?useNumberAsId=true", Content => $dataString);
    my $data_json   = $upload->content;
    $upload_content = SL::JSON::decode_json($data_json);
  }else{
    #upload
    $upload         = $self->connector->post($url . "api/articles/", Content => $dataString);
    my $data_json   = $upload->content;
    $upload_content = SL::JSON::decode_json($data_json);
  }
  # don't know if this is needed
  if(@upload_img) {
    my $partnumber = $::form->escape($part->{partnumber});#shopware don't accept / in articlenumber
    my $imgup      = $self->connector->put($url . "api/generatearticleimages/$partnumber?usenumberasid=true");
  }

  return $upload_content->{success};
}

sub get_article {
  my ($self,$partnumber) = @_;

  my $url       = $self->url;
  $partnumber   = $::form->escape($partnumber);#shopware don't accept / in articlenumber
  my $data      = $self->connector->get($url . "api/articles/$partnumber?usenumberasid=true");
  my $data_json = $data->content;
  return SL::JSON::decode_json($data_json);
}


sub set_orderstatus {
  my ($self,$ordernumber);
}

sub init_url {
  my ($self) = @_;
  $self->url($self->config->protocol . "://" . $self->config->server . ":" . $self->config->port . $self->config->path);
}

sub init_connector {
  my ($self) = @_;
  my $ua = LWP::UserAgent->new;
  $ua->credentials(
      $self->config->server . ":" . $self->config->port,
      $self->config->realm,
      $self->config->login => $self->config->password
  );

  return $ua;

}

1;

__END__

=encoding utf-8

=head1 NAME

  SL::Shopconnecter::Shopware - connector for shopware 5

=head1 SYNOPSIS


=head1 DESCRIPTION

=head1 TODO

  Pricesrules, pricessources aren't fully implemented yet.
  Payments aren't implemented( need to map payments from Shopware like invoice, paypal etc. to payments in kivitendo)

=head1 BUGS

  None yet. :)

=head1 AUTHOR

  W. Hahn E<lt>wh@futureworldsearch.netE<gt>

=cut
