# @tag: SKR04-3804-addition
# @description: Konto 3804 zu SKR04 hinzufügen: Umsatzsteuer 19% für Steuerschlüssel 13 (Umsatzsteuer aus EG-Erwerb)
# @depends:
# @charset: UTF-8

use utf8;
use strict;

die("This script cannot be run from the command line.") unless ($main::form);

sub mydberror {
  my ($msg) = @_;
  die($dbup_locale->text("Database update error:") . "<br>$msg<br>" . $DBI::errstr);
}

sub do_query {
  my ($query, $may_fail) = @_;

  if (!$dbh->do($query)) {
    mydberror($query) unless ($may_fail);
    $dbh->rollback();
    $dbh->begin_work();
  }
}


sub do_update {

  # 1. Überprüfen ob Kontenrahmen SKR04 ist, wenn nicht alles überspringen
  my ($kontenrahmen) = $dbh->selectrow_array("select coa from defaults");

  unless ( $kontenrahmen eq 'Germany-DATEV-SKR04EU' ) {
    print "Kontenrahmen ist nicht SKR04, &uuml;berspringen<br>";
    return 1;
  };

  # Mandant hat SKR04, erst prüfen wir, ob in der Vergangenheit Buchungen mit
  # taxkey 13 erfolgt sind (Fall "EU ohne USt. ID), diese sind wahrscheinlich
  # mit der falschen MwSt (16%) gebucht worden, wenn dies nicht manuell
  # geändert worden ist

  my ($anzahl_buchungen) = $dbh->selectrow_array("select count (*) from acc_trans where taxkey=13 and transdate >= '2007-01-01';");
  if ( $anzahl_buchungen > 0 ) {
    if ($main::form->{bookings_exist} ) {
      # Benutzer hat Meldung bestätigt
      print "Buchungen nach dem 01.01.2007 existierten, Upgrade &uuml;berspringen";
      return 1;  
    } else {
      # Meldung anzeigen und auf Rückgabe warten
      print_past_booking_warning();
      return 2;
    };
  } else {  # es gibt keine Buchungen mit taxkey 13 nach 01.01.2007
  
    # prüfen ob Konto 3804 schon existiert
    my ($konto_existiert) = $dbh->selectrow_array("select count (*) from chart where accno = '3804'");
    if ( $konto_existiert ) {
      # 3804 existiert, wir gehen davon aus, daß der Benutzer das Konto schon selber angelegt hat und
      # ordnungsgemäß benutzt

      if ($main::form->{account_exists} ) {
      # Benutzer hat Meldung bestätigt
        print "Konto existiert, Upgrade &uuml;berspringen\n";
        return 1;  
      } else {
        # Meldung anzeigen und auf Rückgabe warten
        print_3804_already_exists();
        return 2;
      };
    } else {

    # noch keine Buchungen mit taxkey 13 und Konto 3804 existiert noch nicht,
    # also legen wir es an und machen noch die nötigen Einstellungen in tax und
    # taxkeys

        my $insert_chart = <<SQL;
INSERT INTO chart (
  accno, description,
  charttype,   category,  link,
  taxkey_id, pos_eur
  )
SELECT
  '3804','Umsatzsteuer aus EG-Erwerb 19%',
  'A','I','AR_tax:IC_taxpart:IC_taxservice',
  0, (select pos_eur from chart where accno = '3803')
WHERE EXISTS ( -- update only for SKR04, aber eigentlich schon überprüft
    SELECT coa FROM defaults
    WHERE defaults.coa='Germany-DATEV-SKR04EU'
);
SQL

        do_query($insert_chart);

        my $konto_anlegen = $dbh->prepare($insert_chart) || mydberror($insert_chart);


        # 13-1 (16%) korrigieren:
        my $edit_taxkey_13 = qq|UPDATE tax SET taxdescription = 'Steuerpflichtige EG-Lieferung zum vollen Steuersatz', rate = '0.16', chart_id = (select id FROM chart where accno = '3803'), taxnumber = 3803 WHERE taxkey = '13'|;
        do_query($edit_taxkey_13);

        # Sicherstellen, daß 3803 die richtige Bezeichnung hat
        my $update_3803 = qq|update chart set description = 'Umsatzsteuer aus EG-Erwerb 16%' where accno = '3803'|;
        do_query($update_3803);

        # Zweiter  Eintrag für taxkey 13 in key: 19%
        my $insert_taxkey_13_2 = qq|INSERT INTO tax ( taxkey, taxdescription, rate, chart_id, taxnumber ) VALUES ('13', 'Steuerpflichtige EG-Lieferung zum vollen Steuersatz', '0.19', (select id from chart where accno = '3804'), '3804')|;

        do_query($insert_taxkey_13_2);

        # alle Konten finden, bei denen 3803 das Steuerautomatikkonto ist,
        # und dort den zweiten Eintrag ab 1.1.2007 für 19% einstellen
        my $sth_query  = $dbh->prepare(qq|select c.id from chart c join taxkeys t on (c.id = t.chart_id) where tax_id = (select id from tax where taxnumber = '3803')|);
        my $sth_insert = $dbh->prepare(qq|INSERT INTO taxkeys ( taxkey_id, chart_id, tax_id, pos_ustva, startdate )
                                                       VALUES (13, ?, (select id from tax where taxkey = 13 and rate = '0.19'),
            (select pos_ustva from taxkeys where tax_id = (select id from tax where taxnumber = '3803') and pos_ustva > 0 limit 1),
            '01.01.2007')|);
        $sth_query->execute();

        while (my $ref = $sth_query->fetchrow_hashref()) {
          $sth_insert->execute($ref->{id});
        }
        $sth_query->finish();
        $sth_insert->finish();

      }; # end code update
  }; # end check if 3804 exists

}; # end do_update

sub print_past_booking_warning {
  print $main::form->parse_html_template("dbupgrade/SKR04_3804_update");
};
sub print_3804_already_exists {
  print $main::form->parse_html_template("dbupgrade/SKR04_3804_already_exists");
};

return do_update();
