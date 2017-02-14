package SL::Presenter::Invoice;

use strict;

use parent qw(SL::Presenter::Object);
use SL::Locale::String qw(t8);

use Carp;

sub url {
  my ($class, $object, %params) = @_;

  return ($object->invoice ? "is" : "ar") . '.pl?action=edit&type=invoice&id=' . $object->id;
}

sub id {
  join ' ', grep $_, map $_[1]->$_, qw(displayable_type record_number);
}

sub gist {
  my ($class, $self, %params) = @_;

  return sprintf("%s: %s %s %s (%s)", $self->abbreviation, $self->invnumber, $self->customer->name,
                                      $::form->format_amount(\%::myconfig, $self->amount,2), $self->transdate->to_kivitendo);
}

sub state {
  my ($class, $self, %params) = @_;

  $self->closed ? t8('closed') : t8('open');
}

sub type {
  my ($class, $self, %params) = @_;

  return t8('AR Transaction')                         if $self->invoice_type eq 'ar_transaction';
  return t8('Credit Note')                            if $self->invoice_type eq 'credit_note';
  return t8('Invoice') . "(" . t8('Storno') . ")"     if $self->invoice_type eq 'invoice_storno';
  return t8('Credit Note') . "(" . t8('Storno') . ")" if $self->invoice_type eq 'credit_note_storno';
  return t8('Invoice');
}

sub abbreviation {
  my ($class, $self, %params) = @_;

  return t8('AR Transaction (abbreviation)')         if $self->invoice_type eq 'ar_transaction';
  return t8('Credit note (one letter abbreviation)') if $self->invoice_type eq 'credit_note';
  return t8('Invoice (one letter abbreviation)') . "(" . t8('Storno (one letter abbreviation)') . ")" if $self->invoice_type eq 'invoice_storno';
  return t8('Credit note (one letter abbreviation)') . "(" . t8('Storno (one letter abbreviation)') . ")"  if $self->invoice_type eq 'credit_note_storno';
  return t8('Invoice (one letter abbreviation)');
}

1;

__END__

=pod

=encoding utf8

=head1 NAME

SL::Presenter::Invoice - Presenter module for sales invoice, AR
transaction, purchase invoice and AP transaction Rose::DB objects

=head1 SYNOPSIS

  # Sales invoices:
  my $object = SL::DB::Manager::Invoice->get_first(where => [ invoice => 1 ]);
  my $html   = SL::Presenter->get->sales_invoice($object, display => 'inline');

  # AR transactions:
  my $object = SL::DB::Manager::Invoice->get_first(where => [ or => [ invoice => undef, invoice => 0 ]]);
  my $html   = SL::Presenter->get->ar_transaction($object, display => 'inline');

  # Purchase invoices:
  my $object = SL::DB::Manager::PurchaseInvoice->get_first(where => [ invoice => 1 ]);
  my $html   = SL::Presenter->get->purchase_invoice($object, display => 'inline');

  # AP transactions:
  my $object = SL::DB::Manager::PurchaseInvoice->get_first(where => [ or => [ invoice => undef, invoice => 0 ]]);
  my $html   = SL::Presenter->get->ar_transaction($object, display => 'inline');

  # use with any of the above ar/ap/is/ir types:
  my $html   = SL::Presenter->get->invoice($object, display => 'inline');

=head1 FUNCTIONS

=over 4

=item C<invoice $object, %params>

Returns a rendered version (actually an instance of
L<SL::Presenter::EscapedText>) of an ar/ap/is/ir object C<$object> . Determines
which type (sales or purchase, invoice or not) the object is.

C<%params> can include:

=over 2

=item * display

Either C<inline> (the default) or C<table-cell>. At the moment both
representations are identical and produce the invoice number linked
to the corresponding 'edit' action.

=item * no_link

If falsish (the default) then the invoice number will be linked to the
"edit invoice" dialog from the sales menu.

=back

=item C<sales_invoice $object, %params>

Returns a rendered version (actually an instance of
L<SL::Presenter::EscapedText>) of the sales invoice object C<$object>
.

C<%params> can include:

=over 2

=item * display

Either C<inline> (the default) or C<table-cell>. At the moment both
representations are identical and produce the invoice number linked
to the corresponding 'edit' action.

=item * no_link

If falsish (the default) then the invoice number will be linked to the
"edit invoice" dialog from the sales menu.

=back

=item C<ar_transaction $object, %params>

Returns a rendered version (actually an instance of
L<SL::Presenter::EscapedText>) of the AR transaction object C<$object>
.

C<%params> can include:

=over 2

=item * display

Either C<inline> (the default) or C<table-cell>. At the moment both
representations are identical and produce the invoice number linked
to the corresponding 'edit' action.

=item * no_link

If falsish (the default) then the invoice number will be linked to the
"edit invoice" dialog from the general ledger menu.

=back

=item C<purchase_invoice $object, %params>

Returns a rendered version (actually an instance of
L<SL::Presenter::EscapedText>) of the purchase invoice object
C<$object>.

C<%params> can include:

=over 2

=item * display

Either C<inline> (the default) or C<table-cell>. At the moment both
representations are identical and produce the invoice number name
linked to the corresponding 'edit' action.

=item * no_link

If falsish (the default) then the invoice number will be linked to
the "edit invoice" dialog from the purchase menu.

=back

=item C<ap_transaction $object, %params>

Returns a rendered version (actually an instance of
L<SL::Presenter::EscapedText>) of the AP transaction object C<$object>
.

C<%params> can include:

=over 2

=item * display

Either C<inline> (the default) or C<table-cell>. At the moment both
representations are identical and produce the invoice number linked
to the corresponding 'edit' action.

=item * no_link

If falsish (the default) then the invoice number will be linked to the
"edit invoice" dialog from the general ledger menu.

=back

=back

=head1 BUGS

Nothing here yet.

=head1 AUTHOR

Moritz Bunkus E<lt>m.bunkus@linet-services.deE<gt>

=cut
