package SL::Presenter::GLTransaction;

use strict;
use parent qw(SL::Presenter::Object);

use SL::Locale::String qw(t8);
use List::Util qw(sum);

sub url {
  my ($class, $object, %params) = @_;

  return 'gl.pl?action=edit&id=' . $object->id;
}

sub id {
  $_[1]->reference;
}

sub type {
  t8('GL Transaction')
}

sub gist {
  my ($class, $self, %params) = @_;
  my $amount =  sum map { $_->amount > 0 ? $_->amount : 0 } @{$self->transactions};
  $amount = $::form->format_amount(\%::myconfig, $amount, 2);
  return sprintf("%s: %s %s %s (%s)", $self->abbreviation, $self->description, $self->reference, $amount, $self->transdate->to_kivitendo);
}

sub abbreviation {
  my ($class, $self, %params) = @_;

  my $abbreviation = $::locale->text('GL Transaction (abbreviation)');
  $abbreviation   .= "(" . $::locale->text('Storno (one letter abbreviation)') . ")" if $self->storno;
  $abbreviation;
}

1;
