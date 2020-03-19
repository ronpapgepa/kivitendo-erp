package SL::Controller::DownloadZip;

use strict;

use parent qw(SL::Controller::Base);

use utf8;
use IO::Compress::Zip qw(zip $ZipError);
use SL::File;
use SL::SessionFile::Random;

sub action_download_orderitems_files {
  my ($self) = @_;

  #
  # special case for customer which want to have not all
  # in kivitendo.conf some regex may be defined:
  # For no values just let it commented out
  # PA = Produktionsauftrag, L = Lieferschein, ML = Materialliste
  # If you want several options, please separate the letter with '|'. Example: '^(PA|L).*'
  #set_sales_documenttype_for_delivered_quantity = '^(LS).*'
  #set_purchase_documenttype_for_delivered_quantity = '^(EL).*'
  #
  # enbale this perl code:
  #  my $doctype = $::lx_office_conf{system}->{"set_documenttype_for_part_zip_download"};
  #  if ( $doctype ) {
  #    # eliminate first and last char (are quotes)
  #    $doctype =~ s/^.//;
  #    $doctype =~ s/.$//;
  #  }

  #$Archive::Zip::UNICODE = 1;

  my $object_id    = $::form->{object_id};
  my $sfile = SL::SessionFile::Random->new(mode => "w");
  my (@files, %name_subs);

  die "Need a saved object!" unless $object_id;
  die "Works only for Quotations or Orders"
    unless $::form->{object_type} =~ m{^(?:sales_order|purchase_order|sales_quotation|request_quotation)$};

  my $orderitems = SL::DB::Manager::OrderItem->get_all(query => ['order.id' => $object_id ],
                                                       with_objects => [ 'order', 'part' ],
                                                       sort_by => 'part.partnumber ASC');
  foreach my $item ( @{$orderitems} ) {
    my @files_cur = SL::File->get_all(object_id   => $item->parts_id,
                                      object_type => 'part' # this is a mandatory param! get_all can only fetch one type
                                     );
    next unless @files_cur;

    foreach (@files_cur) {
      push @files, $_->get_file;
      $name_subs{$_->get_file} = $item->part->partnumber . '/' . $_->db_file->file_name;
    }
  }
  zip \@files => $sfile->file_name, FilterName => sub { s/.*/$name_subs{$_}/; }
    or die "zip failed: $ZipError\n";

  return $self->send_file(
    $sfile->file_name,
    type => 'application/zip',
    name => $::form->{zipname}.'.zip',
  );
}

1;

__END__

=pod

=encoding utf-8

=head1 NAME

SL::Controller::DownloadZip - controller for download all files from parts of an order in one zip file

=head2  C<action_download_zip FORMPARAMS>

Some customer want all attached files for the parts of an sales order or sales delivery order in one zip to download.
This is a special method for one customer, so it is moved into an extra controller.


There is also a special javascript method necessary which calles this controller method.
THis method must be inserted into the customer branch:

=begin text

  ns.downloadOrderitemsAtt = function(type,id) {
    var rowcount  = $('input[name=rowcount]').val() - 1;
    var data = {
        action:     'FileManagement/download_zip',
        type:       type,
        object_id:  id,
        rowcount:   rowcount
    };
    if ( rowcount == 0 ) {
        kivi.display_flash('error', kivi.t8('No articles have been added yet.'));
        return false;
    }
    for (var i = 1; i <= rowcount; i++) {
        data['parts_id_'+i] =  $('#id_' + i).val();
    };
    $.download("controller.pl", data);
    return false;
  }

=end text

See also L<SL::Controller::FileManagement>

=head1 DISCUSSION

Is this method needed in the master branch ?

No. But now we've got it.
The pod is not quite accurate, sales delivery order is not a valid record_type
for this Controller.

=head1 AUTHOR

Martin Helmling E<lt>martin.helmling@opendynamic.deE<gt>

=cut
