package SL::Presenter::PurchaseInvoice;

use strict;

use parent qw(SL::Presenter::Object);

use SL::Locale::String qw(t8);
use Carp;

sub url {
  my ($class, $object, %params) = @_;

  return ($object->invoice ? "ir" : "ap") . '.pl?action=edit&type=invoice&id=' . $object->id;
}

sub id {
  join ' ', grep $_, map $_[1]->$_, qw(displayable_type record_number);
}

sub gist {
  my ($class, $self, %params) = @_;

  return sprintf("%s: %s %s %s (%s)", $self->abbreviation, $self->invnumber, $self->vendor->name,
                                      $::form->format_amount(\%::myconfig, $self->amount,2), $self->transdate->to_kivitendo);
}

sub state {
  my ($class, $self, %params) = @_;

  $self->closed ? t8('closed') : t8('open');
}

sub type {
  my ($class, $self, %params) = @_;

  return t8('AP Transaction')    if $self->invoice_type eq 'ap_transaction';
  return t8('Purchase Invoice');

}

sub abbreviation {
  my ($class, $self, %params) = @_;

  return t8('AP Transaction (abbreviation)') if !$self->invoice && !$self->storno;
  return t8('AP Transaction (abbreviation)') . '(' . t8('Storno (one letter abbreviation)') . ')' if !$self->invoice && $self->storno;
  return t8('Invoice (one letter abbreviation)'). '(' . t8('Storno (one letter abbreviation)') . ')' if $self->storno;
  return t8('Invoice (one letter abbreviation)');
}

1;
