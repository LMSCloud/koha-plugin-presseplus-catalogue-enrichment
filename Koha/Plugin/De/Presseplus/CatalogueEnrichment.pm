package Koha::Plugin::De::Presseplus::CatalogueEnrichment;

# Koha is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# Koha is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Koha; if not, see <http://www.gnu.org/licenses>.

use Modern::Perl;

use base qw(Koha::Plugins::Base);

use C4::Context;
use C4::Auth;
use Koha::Biblios;
use Koha::Items;
use Koha::Patrons;
use Koha::CoverImages;
use Mojo::JSON qw(decode_json);;
use File::Temp qw(tempfile);
use GD::Image;

our $VERSION = "0.01";
our $MINIMUM_VERSION = "20.06";

our $metadata = {
    name            => 'Catalogue enrichment plugin for Presseplus',
    author          => 'Jonathan Druart',
    date_authored   => '2020-07-23',
    date_updated    => "1900-01-01",
    minimum_version => $MINIMUM_VERSION,
    maximum_version => undef,
    version         => $VERSION,
    description     => 'This plugin retrieves some information from Presseplus to enrich a Koha catalogue',
};

sub new {
    my ( $class, $args ) = @_;

    $args->{'metadata'} = $metadata;
    $args->{'metadata'}->{'class'} = $class;

    my $self = $class->SUPER::new($args);

    $self->{cgi} = CGI->new();

    return $self;
}

sub tool {
    my ( $self, $args ) = @_;

    my $cgi = $self->{'cgi'};

    unless ( $cgi->param('submitted') ) {
        $self->tool_step1();
    }
    else {
        $self->tool_step2();
    }
}

sub opac_head {
    my ( $self ) = @_;

    return q|
        <style>
          body {
          }
        </style>
    |;
}

sub opac_js {
    my ( $self ) = @_;

    return q|
    |;
}

sub intranet_head {
    my ( $self ) = @_;

    return q|
        <style>
          body {
          }
        </style>
    |;
}

sub intranet_js {
    my ( $self ) = @_;

    return sprintf q|
        <script>
            $('<li><a href="/cgi-bin/koha/plugins/run.pl?class=%s&method=catalogue&biblionumber=%s">New item from Presseplus</a></li>').insertAfter($("#newitem").parent());
        </script>
    |, $self->{metadata}->{class}, $self->{cgi}->param('biblionumber');
}

sub intranet_catalog_biblio_enhancements_toolbar_button {
    my ( $self ) = @_;
    my $template = $self->get_template({
        file => 'toolbar-button.tt'
    });
    $template->param(
        biblionumber => scalar $self->{cgi}->param('biblionumber')
    );
    $template->output;
}

sub configure {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};

    unless ( $cgi->param('save') ) {
        my $template = $self->get_template({ file => 'configure.tt' });

        $template->param(
            apikey => $self->retrieve_data('apikey'),
            coversize => $self->retrieve_data('coversize'),
        );

        $self->output_html( $template->output() );
    }
    else {
        $self->store_data(
            {
                apikey => scalar $cgi->param('apikey'),
                coversize => scalar $cgi->param('coversize'),
            }
        );
        $self->go_home();
    }
}

## This is the 'install' method. Any database tables or other setup that should
## be done when the plugin if first installed should be executed in this method.
## The installation method should always return true if the installation succeeded
## or false if it failed.
sub install() {
    my ( $self, $args ) = @_;

    #    my $table = $self->get_qualified_table_name('configuration');
    #
    #    return C4::Context->dbh->do( "
    #        CREATE TABLE IF NOT EXISTS $table (
    #            `apikey` VARCHAR( 255 ) NOT NULL DEFAULT ''
    #        ) ENGINE = INNODB;
    #    " );
}

## This is the 'upgrade' method. It will be triggered when a newer version of a
## plugin is installed over an existing older version of a plugin
sub upgrade {
    my ( $self, $args ) = @_;

    my $dt = dt_from_string();
    $self->store_data( { last_upgraded => $dt->ymd('-') . ' ' . $dt->hms(':') } );

    return 1;
}

## This method will be run just before the plugin files are deleted
## when a plugin is uninstalled. It is good practice to clean up
## after ourselves!
sub uninstall() {
    my ( $self, $args ) = @_;

    #    my $table = $self->get_qualified_table_name('configuration');
    #
    #    return C4::Context->dbh->do("DROP TABLE IF EXISTS $table");
}

sub tool_step1 {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};

    my $template = $self->get_template({ file => 'tool-step1.tt' });

    $self->output_html( $template->output() );
}

sub tool_step2 {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};

    #apikey => $self->retrieve_data('apikey'),
    my $template = $self->get_template({ file => 'tool-step2.tt' });

    my $issn_ean = $cgi->param('issn_ean'); # FIXME Should be in the response, is that issn or ean?
    my $release_code = $cgi->param('release_code');
    # TODO
    # my $json = REST API call
    # my $struct = from_json $json;
    # TODO handle errors
    my $struct = {
        "name"        => 'BRAVO',
        "description" => "Größte Jugendzeitschrift",
        "evt"         => "2018-08-01T00:00:00",
        "releaseCode" => "2018017",
        "contentList" => [
            {
                "headline" => "Reich durch Klicks: Traumjob Webstar! Hast du das Zeugdazu?",
                "content" =>
                  "+ Die besten Fame-Tricks von Dagi, Julien & Co."
            },
            {
                "headline" => "Vergiss mich nicht",
                "content" =>
                  "Wie deine Ferienliebe etwas Besonderes wird..."
            },
            {
                "headline" => "Was ist los mit Justin?",
                "content"  => "Seine crazy Verwandlung"
            }
        ]
    };
    my $default_itemtype = 'BK'; # FIXME Must be configurable
    $struct->{evt} =~ s|^(\d{4}-\d{2}-\d{2}).*$|$1|; # FIXME other format needed?
    # 245$a = BRAVO
    #    $n = 2018017
    #    $p = "Größte Jugendzeitschrift"
    my $record = MARC::Record->new;
    $record->append_fields(
        MARC::Field->new(
            '245', '0', '0',
            'a' => $struct->{name},
            'n' => $struct->{releaseCode},
            'p' => $struct->{description},
        )
    );
    $record->append_fields(
        MARC::Field->new( '260', '0', '0', 'c' => $struct->{evt}, ) );
    for my $toc (@{$struct->{contentList}}) {
        $record->append_fields(
            MARC::Field->new(
                '505', '0', '',
                # FIXME in a or t?
                #'a' => sprintf ("%s - %s", $toc->{headline}, $toc->{content}),
                't' => sprintf ("%s - %s", $toc->{headline}, $toc->{content}),
            ) );    # FIXME How to display "headline - content"?
    }

    $record->append_fields(
        MARC::Field->new( '942', '0', '0', 'c' => $default_itemtype ) );

    my ( $biblionumber ) = C4::Biblio::AddBiblio($record, ''); # FIXME Maybe we want the framworkcode to be an option?

    my $logged_in_user = Koha::Patrons->find( C4::Context->userenv->{number} );
    Koha::Item->new(
        {
            biblionumber  => $biblionumber,
            barcode       => undef,                         # FIXME No barcode?
            homebranch    => $logged_in_user->branchcode,
            holdingbranch => $logged_in_user->branchcode,
            itype         => $default_itemtype,
            # FIXME notforloan status? Otherwise it's "available"
        }
    )->store;

    my ($fh, $fn ) = tempfile( SUFFIX => '.cover', UNLINK => 1 );
    my $cmd = sprintf q{wget -O %s https://cover.presseplus.eu/%s/%s/%s}, $fn, $self->retrieve_data('coversize')||200, $issn_ean, $release_code;
    my $r = qx{$cmd}; # FIXME handle error
    my $srcimage = GD::Image->new($fh);
    Koha::CoverImage->new({ biblionumber => $biblionumber, src_image => $srcimage })->store; # FIXME handle error

    $template->param(
        biblio => Koha::Biblios->find($biblionumber),
        plugin => $self,
    );

    $self->output_html( $template->output() );
}

sub catalogue {
    my ($self, $args) = @_;

    my $cgi = $self->{cgi};
    my $template = $self->get_template({
        file => 'catalogue.tt'
    });

    # The biblio we're working with
    my $biblionumber = $self->{cgi}->param('biblionumber');
    my $biblio = Koha::Biblios->find( $biblionumber );
    die "no biblio for biblionumber=$biblionumber" unless $biblio; # FIXME handle that gracefully

    $template->param(
        biblio => $biblio,
        apikey => $self->retrieve_data('apikey'),
    );

    if ( $cgi->param('submitted') ) {

        my $issn_ean = $cgi->param('issn_ean'); # FIXME Should be in the response, is that issn or ean?
        my $release_code = $cgi->param('release_code');
        # TODO
        # my $json = REST API call
        # my $struct = from_json $json;
        # TODO handle errors
        my $struct = {
            "name"        => 'BRAVO',
            "description" => "Größte Jugendzeitschrift",
            "evt"         => "2018-08-01T00:00:00", # FIXME Where to store this date for items?
            "releaseCode" => "2018017",
            "contentList" => [
                {
                    "headline" => "Reich durch Klicks: Traumjob Webstar! Hast du das Zeugdazu?",
                    "content" =>
                      "+ Die besten Fame-Tricks von Dagi, Julien & Co."
                },
                {
                    "headline" => "Vergiss mich nicht",
                    "content" =>
                      "Wie deine Ferienliebe etwas Besonderes wird..."
                },
                {
                    "headline" => "Was ist los mit Justin?",
                    "content"  => "Seine crazy Verwandlung"
                }
            ]
        };
        my $default_itemtype = 'BK'; # FIXME Must be configurable
        $struct->{evt} =~ s|^(\d{4}-\d{2}-\d{2}).*$|$1|; # FIXME other format needed?
        # 245$a = BRAVO
        #    $n = 2018017
        #    $p = "Größte Jugendzeitschrift"

        my $logged_in_user = Koha::Patrons->find( C4::Context->userenv->{number} );

        my @tocs;
        for my $toc (@{$struct->{contentList}}) {
            push @tocs, sprintf ("%s - %s", $toc->{headline}, $toc->{content}),
        }

        my $item = Koha::Item->new(
            {
                biblionumber  => $biblionumber,
                barcode       => undef,                         # FIXME No barcode?
                homebranch    => $logged_in_user->branchcode,
                holdingbranch => $logged_in_user->branchcode,
                itype         => $default_itemtype,
                itemnotes     => join "\n", @tocs,
            # FIXME notforloan status? Otherwise it's "available"
            }
        )->store;

        my ($fh, $fn ) = tempfile( SUFFIX => '.cover', UNLINK => 1 );
        my $cmd = sprintf q{wget -O %s https://cover.presseplus.eu/%s/%s/%s}, $fn, $self->retrieve_data('coversize')||200, $issn_ean, $release_code;
        my $r = qx{$cmd}; # FIXME handle error
        my $srcimage = GD::Image->new($fh);
        Koha::CoverImage->new({ itemnumber => $item->itemnumber, src_image => $srcimage })->store; # FIXME handle error

        $template->param(
            biblio => Koha::Biblios->find($biblionumber),
            plugin => $self,
        );
        print $cgi->redirect("/cgi-bin/koha/catalogue/detail.pl?biblionumber=$biblionumber");
        exit;
    }

    $self->output_html( $template->output );
}

1;
