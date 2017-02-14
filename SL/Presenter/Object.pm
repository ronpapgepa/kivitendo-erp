package SL::Presenter::Object;

use strict;
use SL::Presenter;
use SL::Presenter::EscapedText;

sub link_tag {
  my ($class, $object, %params) = @_;

  SL::Presenter->escaped_text(
    SL::Presenter::Tag::link(
      SL::Presenter->get,
      $class->url($object, %params),
      $class->id($object, %params),
      %params
    ),
  );
}

sub url {
  my ($class, $object, %params) = @_;

  die 'must be overridden';
}

sub id {
  my ($class, $object, %params) = @_;

  die 'must be overridden';
}

sub gist {
  my ($class, $object, %params) = @_;

  die 'must be overridden';
}

sub table_cell {
  goto &link_tag;
}

sub inline {
  goto &link_tag;
}

sub render {
  my ($class, $object, %params) = @_;

  my $display = delete $params{display} || 'inline';

  die "Unknown display type '$display'" unless $display && $class->can($display);

  $class->$display($object, %params);
}

sub picker {
  my ($class, $object, %params) = @_;

  die 'must be overridden';
}

1;

__END__

=encoding utf-8

=head1 NAME

SL::Presenter::Object - base class for typed presenters

=head1 SYNOPSIS

  # use as base class for presenter:
  use parent qw(SL::Presenter::Object);

  # implement some often used things
  # all of these have signature ($class, $object, %params)
  sub gist { $_[1]->number . ' ' . $_[1]->name }
  sub url { 'controller.pl?action=This/edit&id=' . $_[1]->id }

=head1 CALLING CONVENTION

All methods in classes derived from this should have the signature C<$class,
$object, %params>. This way a proxy in C<SL::DB::Object> can be used to call
these methods on single objects.

=head1 METHODS

=over 4

=item C<url $class, $object, %params>

Returns an url to this object. Should handle callbacks.

Must be overridden.

=item C<id $class, $object, %params>

Returns an identification of the object intended for human readers. Should be
as concise and unique as possible.

Must be overridden

=item C<gist $class, $object, %params>

Returns a summary of the object. Should be one serialized line with as much
information as possible.

Must be overridden

=item C<link_tag $class, $object, %params>

Returns a link build from L<url> and L<id>.

=item C<table_cell $class, $object, %params>

Returns a presentation of this object intended for table cells.

Defaults to L<link_tag>.

=item C<inline $class, $object, %params>

Returns a presentation of this object intended for inlining in text.

Defaults to L<link_tag>.

=item C<render $class, $object, %params>

A dispatch method that extracts C<display> from params and calls the
appropriate method. If no C<display> is given, defaults to C<inline> for
historical reasons.

=item C<picker $class, $object, %params>

Renders a picker. If C<$object> is given it will be used as preselection.

Must be overridden.

=back

=head1 BUGS

I'm won't tell!

=head1 AUTHOR

Sven Schöling E<lt>s.schoeling@linet-services.deE<gt>

=cut
