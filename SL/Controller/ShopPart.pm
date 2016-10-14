package SL::Controller::ShopPart;
#package SL::Controller::ShopPart;

use strict;

use parent qw(SL::Controller::Base);

use SL::BackgroundJob::ShopPartMassUpload;
use SL::System::TaskServer;
use Data::Dumper;
use SL::Locale::String qw(t8);
use SL::DB::ShopPart;
use SL::DB::File;
use SL::Controller::FileUploader;
use SL::DB::Default;
use SL::Helper::Flash;
use MIME::Base64;

use Rose::Object::MakeMethods::Generic
(
   scalar                 => [ qw(price_sources) ],
  'scalar --get_set_init' => [ qw(shop_part file shops producers) ],
);

__PACKAGE__->run_before('check_auth');
__PACKAGE__->run_before('add_javascripts', only => [ qw(edit_popup list_articles) ]);
__PACKAGE__->run_before('load_pricesources',    only => [ qw(create_or_edit_popup) ]);

#
# actions
#

sub action_create_or_edit_popup {
  my ($self) = @_;

  $self->render_shop_part_edit_dialog();
}

sub action_update_shop {
  my ($self, %params) = @_;

  my $shop_part = SL::DB::Manager::ShopPart->find_by(id => $::form->{shop_part_id});
  die unless $shop_part;

  require SL::Shop;
  my $shop = SL::Shop->new( config => $shop_part->shop );

  my $part_hash = $shop_part->part->as_tree;
  my $json      = SL::JSON::to_json($part_hash);
  my $return    = $shop->connector->update_part($self->shop_part, $json,'all');

  # the connector deals with parsing/result verification, just needs to return success or failure
  if ( $return == 1 ) {
    my $now = DateTime->now;
    my $attributes->{last_update} = $now;
    $self->shop_part->assign_attributes(%{ $attributes });
    $self->shop_part->save;
    $self->js->html('#shop_part_last_update_' . $shop_part->id, $now->to_kivitendo('precision' => 'minute'))
           ->flash('info', t8("Updated part [#1] in shop [#2] at #3", $shop_part->part->displayable_name, $shop_part->shop->description, $now->to_kivitendo('precision' => 'minute') ) )
           ->render;
  } else {
    $self->js->flash('error', t8('The shop part wasn\'t updated.'))->render;
  };

}

sub action_show_files {
  my ($self) = @_;

  my $images = SL::DB::Manager::File->get_all_sorted( where => [ trans_id => $::form->{id}, modul => $::form->{modul}, file_content_type => { like => 'image/%' } ], sort_by => 'position' );

  $self->render('shop_part/_list_images', { header => 0 }, IMAGES => $images);
}

sub action_ajax_upload_file{
  my ($self, %params) = @_;

  my $attributes                   = $::form->{ $::form->{form_prefix} } || die "Missing attributes";

  $attributes->{filename} = ((($::form->{ATTACHMENTS} || {})->{ $::form->{form_prefix} } || {})->{file_content} || {})->{filename};

  my @errors;
  my @file_errors = SL::DB::File->new(%{ $attributes })->validate;
  push @errors,@file_errors if @file_errors;

  my @type_error = SL::Controller::FileUploader->validate_filetype($attributes->{filename},$::form->{aft});
  push @errors,@type_error if @type_error;

  return $self->js->error(@errors)->render($self) if @errors;

  $self->file->assign_attributes(%{ $attributes });
  $self->file->file_update_type_and_dimensions;
  $self->file->save;

  $self->js
    ->dialog->close('#jqueryui_popup_dialog')
    ->run('kivi.shop_part.show_images',$self->file->trans_id)
    ->render();
}

sub action_ajax_update_file{
  my ($self, %params) = @_;

  my $attributes                   = $::form->{ $::form->{form_prefix} } || die "Missing attributes";

  if (!$attributes->{file_content}) {
    delete $attributes->{file_content};
  } else {
    $attributes->{filename} = ((($::form->{ATTACHMENTS} || {})->{ $::form->{form_prefix} } || {})->{file_content} || {})->{filename};
  }

  my @errors;
  my @type_error = SL::Controller::FileUploader->validate_filetype($attributes->{filename},$::form->{aft});
  push @errors,@type_error if @type_error;
  $self->file->assign_attributes(%{ $attributes });
  my @file_errors = $self->file->validate if $attributes->{file_content};;
  push @errors,@file_errors if @file_errors;

  return $self->js->error(@errors)->render($self) if @errors;

  $self->file->file_update_type_and_dimensions if $attributes->{file_content};
  $self->file->save;

  $self->js
    ->dialog->close('#jqueryui_popup_dialog')
    ->run('kivi.shop_part.show_images',$self->file->trans_id)
    ->render();
}

sub action_ajax_delete_file {
  my ( $self ) = @_;
  $self->file->delete;

  $self->js
    ->run('kivi.shop_part.show_images',$self->file->trans_id)
    ->render();
}

sub action_get_categories {
  my ($self) = @_;

  require SL::Shop;
  my $shop = SL::Shop->new( config => $self->shop_part->shop );
  my $categories = $shop->connector->get_categories;

  $self->js
    ->run(
      'kivi.shop_part.shop_part_dialog',
      t8('Shopcategories'),
      $self->render('shop_part/categories', { output => 0 }, CATEGORIES => $categories )
    )
    ->reinit_widgets;

  $self->js->render;
}

sub action_update {
  my ($self) = @_;

  $self->create_or_update;
}

sub action_show_price_n_pricesource {
  my ($self) = @_;

  my ( $price, $price_src_str ) = $self->get_price_n_pricesource($::form->{pricesource});

  $self->js->html('#price_' . $self->shop_part->id, $::form->format_amount(\%::myconfig,$price,2))
           ->html('#active_price_source_' . $self->shop_part->id, $price_src_str)
           ->render;
}

sub action_show_stock {
  my ($self) = @_;
  my ( $stock_local, $stock_onlineshop, $active_online );

  require SL::Shop;
  my $shop = SL::Shop->new( config => $self->shop_part->shop );

  if($self->shop_part->last_update) {
    my $shop_article = $shop->connector->get_article($self->shop_part->part->partnumber);
    $stock_onlineshop = $shop_article->{data}->{mainDetail}->{inStock};
    $active_online = $shop_article->{data}->{active};
    #}

  $stock_local = $self->shop_part->part->onhand;

  $self->js->html('#stock_' . $self->shop_part->id, $::form->format_amount(\%::myconfig,$stock_local,0)."/".$::form->format_amount(\%::myconfig,$stock_onlineshop,0))
           ->html('#toogle_' . $self->shop_part->id,$active_online)
           ->render;
}

sub action_get_n_write_categories {
  my ($self) = @_;

  my @shop_parts =  @{ $::form->{shop_parts_ids} || [] };
  foreach my $part(@shop_parts){

    my $shop_part = SL::DB::Manager::ShopPart->get_all( where => [id => $part], with_objects => ['part', 'shop'])->[0];
    require SL::DB::Shop;
    my $shop = SL::Shop->new( config => $shop_part->shop );
    my $online_article = $shop->connector->get_article($shop_part->part->partnumber);
    my $online_cat = $online_article->{data}->{categories};
    my @cat = ();
    for(keys %$online_cat){
    # The ShopwareConnector works with the CategoryID @categories[x][0] in others/new Connectors it must be tested
    # Each assigned categorie is saved with id,categorie_name an multidimensional array and could be expanded with categoriepath or what is needed
      my @cattmp;
      push( @cattmp,$online_cat->{$_}->{id} );
      push( @cattmp,$online_cat->{$_}->{name} );
      push( @cat,\@cattmp );
    }
    my $attributes->{shop_category} = \@cat;
    my $active->{active} = $online_article->{data}->{active};
    $shop_part->assign_attributes(%{$attributes}, %{$active});
    $shop_part->save;
  }
  $self->redirect_to( action => 'list_articles' );
}

sub create_or_update {
  my ($self) = @_;

  my $is_new = !$self->shop_part->id;

  # in edit.html all variables start with shop_part
  my $params = delete($::form->{shop_part}) || { };

  $self->shop_part->assign_attributes(%{ $params });

  $self->shop_part->save;

  my ( $price, $price_src_str ) = $self->get_price_n_pricesource($self->shop_part->active_price_source);

  #TODO Price must be formatted. $price_src_str must be translated
  flash('info', $is_new ? t8('The shop part has been created.') : t8('The shop part has been saved.'));
  # $self->js->val('#partnumber', 'ladida');
  $self->js->html('#shop_part_description_' . $self->shop_part->id, $self->shop_part->shop_description)
           ->html('#shop_part_active_' . $self->shop_part->id, $self->shop_part->active)
           ->html('#price_' . $self->shop_part->id, $::form->format_amount(\%::myconfig,$price,2))
           ->html('#active_price_source_' . $self->shop_part->id, $price_src_str)
           ->run('kivi.shop_part.close_dialog')
           ->flash('info', t8("Updated shop part"))
           ->render;
}

sub render_shop_part_edit_dialog {
  my ($self) = @_;

  # when self->shop_part is called in template, it will be an existing shop_part with id,
  # or a new shop_part with only part_id and shop_id set
  $self->js
    ->run(
      'kivi.shop_part.shop_part_dialog',
      t8('Shop part'),
      $self->render('shop_part/edit', { output => 0 }) #, shop_part => $self->shop_part)
    )
    ->reinit_widgets;

  $self->js->render;
}

sub action_save_categories {
  my ($self) = @_;

  my @categories =  @{ $::form->{categories} || [] };

    # The ShopwareConnector works with the CategoryID @categories[x][0] in others/new Connectors it must be tested
    # Each assigned categorie is saved with id,categorie_name an multidimensional array and could be expanded with categoriepath or what is needed
    my @cat = ();
    foreach my $cat ( @categories) {
      my @cattmp;
      push( @cattmp,$cat );
      push( @cattmp,$::form->{"cat_id_${cat}"} );
      push( @cat,\@cattmp );
    }

  my $categories->{shop_category} = \@cat;

  my $params = delete($::form->{shop_part}) || { };

  $self->shop_part->assign_attributes(%{ $params });
  $self->shop_part->assign_attributes(%{ $categories });

  $self->shop_part->save;

  flash('info', t8('The categories has been saved.'));

  $self->js->run('kivi.shop_part.close_dialog')
           ->flash('info', t8("Updated categories"))
           ->render;
}

sub action_reorder {
  my ($self) = @_;

  require SL::DB::File;
  SL::DB::File->reorder_list(@{ $::form->{image_id} || [] });

  $self->render(\'', { type => 'json' });
}

sub action_list_articles {
  my ($self) = @_;

  my %filter = ($::form->{filter} ? parse_filter($::form->{filter}) : query => [ transferred => 0 ]);
  my $transferred = $::form->{filter}->{transferred_eq_ignore_empty} ne '' ? $::form->{filter}->{transferred_eq_ignore_empty} : '';
  my $sort_by = $::form->{sort_by} ? $::form->{sort_by} : 'part.partnumber';
  $sort_by .=$::form->{sort_dir} ? ' DESC' : ' ASC';
$main::lxdebug->message(0, "WH:LA ");

  my $articles = SL::DB::Manager::ShopPart->get_all(where => [ 'shop.obsolete' => 0 ],with_objects => [ 'part','shop' ], sort_by => $sort_by );

  foreach my $article (@{ $articles}) {
    my $images = SL::DB::Manager::File->get_all_count( where => [ trans_id => $article->part->id, modul => 'shop_part', file_content_type => { like => 'image/%' } ], sort_by => 'position' );
    $article->{images} = $images;
  }
  $main::lxdebug->dump(0, 'WH:ARTIKEL ',\$articles);

  $self->render('shop_part/_list_articles', title => t8('Webshops articles'), SHOP_PARTS => $articles);
}

sub action_upload_status {
  my ($self) = @_;
  my $job     = SL::DB::BackgroundJob->new(id => $::form->{job_id})->load;
  my $html    = $self->render('shop_part/_upload_status', { output => 0 }, job => $job);

  $self->js->html('#status_mass_upload', $html);
  $self->js->run('kivi.shop_part.massUploadFinished') if $job->data_as_hash->{status} == SL::BackgroundJob::ShopPartMassUpload->DONE();
  $self->js->render;
}

sub action_mass_upload {
  my ($self) = @_;
$main::lxdebug->message(0, "WH:MA ");

  my @shop_parts =  @{ $::form->{shop_parts_ids} || [] };

  my $job                   = SL::DB::BackgroundJob->new(
    type                    => 'once',
    active                  => 1,
    package_name            => 'ShopPartMassUpload',
  )->set_data(
     shop_part_record_ids         => [ @shop_parts ],
     todo                         => $::form->{upload_todo},
     status                       => SL::BackgroundJob::ShopPartMassUpload->WAITING_FOR_EXECUTION(),
     conversation_errors          => [ ],
   )->update_next_run_at;
$main::lxdebug->dump(0, 'WH:MA JOB ',\$job);

   SL::System::TaskServer->new->wake_up;
$main::lxdebug->dump(0, 'WH:MA JOB 2',\$job);

   my $html = $self->render('shop_part/_transfer_status', { output => 0 }, job => $job);

   $self->js
      ->html('#status_mass_upload', $html)
      ->run('kivi.shop_part.massUploadStarted')
      ->render;
}

#
# internal stuff
#
sub add_javascripts  {
  # is this needed?
  $::request->{layout}->add_javascripts(qw(kivi.shop_part.js));
}

sub load_pricesources {
  my ($self) = @_;

  # the price sources to use for the article: sellprice, lastcost,
  # listprice, or one of the pricegroups. It overwrites the default pricesource from the shopconfig.
  # TODO: implement valid pricerules for the article
  my $pricesources;
  push( @{ $pricesources } , { id => "master_data/sellprice", name => t8("Master Data")." - ".t8("Sellprice") },
                             { id => "master_data/listprice", name => t8("Master Data")." - ".t8("Listprice") },
                             { id => "master_data/lastcost",  name => t8("Master Data")." - ".t8("Lastcost") }
                             );
  my $pricegroups = SL::DB::Manager::Pricegroup->get_all;
  foreach my $pg ( @$pricegroups ) {
    push( @{ $pricesources } , { id => "pricegroup/".$pg->id, name => t8("Pricegroup") . " - " . $pg->pricegroup} );
  };

  $self->price_sources( $pricesources );
}

sub get_price_n_pricesource {
  my ($self,$pricesource) = @_;

  my ( $price_src_str, $price_src_id ) = split(/\//,$pricesource);

  require SL::DB::Pricegroup;
  require SL::DB::Part;
  #TODO Price must be formatted. Translations for $price_grp_str
  my $price;
  if ($price_src_str eq "master_data") {
    my $part = SL::DB::Manager::Part->get_all( where => [id => $self->shop_part->part_id], with_objects => ['prices'],limit => 1)->[0];
    $price = $part->$price_src_id;
    $price_src_str = $price_src_id;
  }else{
    my $part = SL::DB::Manager::Part->get_all( where => [id => $self->shop_part->part_id, 'prices.'.pricegroup_id => $price_src_id], with_objects => ['prices'],limit => 1)->[0];
    my $pricegrp = SL::DB::Manager::Pricegroup->find_by( id => $price_src_id )->pricegroup;
    $price =  $part->prices->[0]->price;
    $price_src_str = $pricegrp;
  }
  return($price,$price_src_str);
}

sub check_auth {
  return 1; # TODO: implement shop rights
  # $::auth->assert('shop');
}

sub init_shop_part {
  if ($::form->{shop_part_id}) {
    SL::DB::Manager::ShopPart->find_by(id => $::form->{shop_part_id});
  } else {
    SL::DB::ShopPart->new(shop_id => $::form->{shop_id}, part_id => $::form->{part_id});
  };
}

sub init_file {
  $main::lxdebug->message(0, "WH:INIT_FILES ");
  my $file = $::form->{id} ? SL::DB::File->new(id => $::form->{id})->load : SL::DB::File->new;
  $main::lxdebug->dump(0, 'WH: INITFILE: ',\file);

  return $file;
}

sub init_shops {
  # data for drop down filter options
  $main::lxdebug->message(0, "WH:INIT_SHOPS ");

  require SL::DB::Shop;
  my @shops_dd = [ { title => t8("all") ,   value =>'' } ];
  my $shops = SL::DB::Mangager::Shop->get_all( where => [ obsolete => 0 ] );
   my @tmp = map { { title => $_->{description}, value => $_->{id} } } @{ $shops } ;
 $main::lxdebug->dump(0, 'WH:SHOPS ',\@tmp);
 return @shops_dd;

}

sub init_producers {
  # data for drop down filter options
  $main::lxdebug->message(0, "WH:INIT_PRODUCERS ");

  my @producers_dd = [ { title => t8("all") ,   value =>'' } ];
 return @producers_dd;

}

1;

__END__

=encoding utf-8


=head1 NAME

  SL::Controller::ShopPart - Controller for managing ShopParts

=head1 SYNOPSIS

  ShopParts are configured in a tab of the corresponding part.

=head1 FUNCTIONS


=over 4


=item C<action_update_shop>

  To be called from the "Update" button of the shoppart, for manually syncing/upload one part with its shop. Generates a  Calls some ClientJS functions to modifiy original page.

=item C<action_get_n_write_categories>

  Can be used to sync the categories of a shoppart with the categories from online.

=head1 AUTHORS

  G. Richardson E<lt>information@kivitendo-premium.deE<gt>
  W. Hahn E<lt>wh@futureworldsearch.netE<gt>

=cut
