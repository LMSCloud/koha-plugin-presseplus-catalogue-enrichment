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
use C4::Charset;
use C4::Search;        # enabled_staff_search_views
use Koha::BiblioFrameworks;
use Koha::Biblios;
use Koha::Items;
use Koha::ItemTypes;
use Koha::Patrons;
use Koha::CoverImages;
use GD::Image;
use LWP::UserAgent;
use HTTP::Request;
use JSON qw( decode_json );

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

    return q|| unless $self->retrieve_data('can_be_grouped');

    my $biblionumber = $self->{cgi}->param('biblionumber');
    return q|| unless $biblionumber;
    return sprintf q|
        <script>
            $('<li><a href="/cgi-bin/koha/plugins/run.pl?class=%s&method=catalogue&biblionumber=%s">New item from Presseplus</a></li>').insertAfter($("#newitem").parent());
        </script>
    |, $self->{metadata}->{class}, $biblionumber;
}

sub intranet_catalog_biblio_enhancements_toolbar_button {
    my ( $self ) = @_;

    return unless $self->retrieve_data('can_be_grouped');

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
            apikey            => $self->retrieve_data('apikey'),
            coversize         => $self->retrieve_data('coversize'),
            can_be_grouped    => $self->retrieve_data('can_be_grouped'),
            toc_image         => $self->retrieve_data('toc_image'),
            default_itemtype  => $self->retrieve_data('default_itemtype'),
            itemtypes         => scalar Koha::ItemTypes->search,
            default_framework => $self->retrieve_data('default_framework'),
            frameworks        => scalar Koha::BiblioFrameworks->search,
        );

        $self->output_html( $template->output() );
    }
    else {
        $self->store_data(
            {
                apikey            => scalar $cgi->param('apikey'),
                coversize         => scalar $cgi->param('coversize'),
                can_be_grouped    => scalar $cgi->param('can_be_grouped'),
                toc_image         => scalar $cgi->param('toc_image'),
                default_itemtype  => scalar $cgi->param('default_itemtype'),
                default_framework => scalar $cgi->param('default_framework'),
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

    my $template = $self->get_template({ file => 'tool-step2.tt' });

    my $issn_ean = $cgi->param('issn_ean'); # FIXME Should be in the response, is that issn or ean?
    my $release_code = $cgi->param('release_code');

    $issn_ean = '4190191702107'; $release_code = '2020005'; # FIXME RMME hardcoded

    my $presseplus_info = $self->retrieve_info( $issn_ean, $release_code );
    my $biblionumber = $self->build_biblio(
        {
            title            => $presseplus_info->{name},
            number           => $presseplus_info->{releaseCode},
            description      => $presseplus_info->{description},
            publication_date => $presseplus_info->{evt},
            table_of_content => $presseplus_info->{contentList}
        }
    );

    my $item = $self->build_item({biblionumber => $biblionumber});

    my $image = $self->retrieve_cover_image( $issn_ean, $release_code );
    Koha::CoverImage->new({ biblionumber => $biblionumber, src_image => $image })->store; # FIXME handle error

    if ( $self->retrieve_data('toc_image') ) {
        my $toc_image = $self->retrieve_toc_image( $issn_ean, $release_code );
        Koha::CoverImage->new({ itemnumber => $item->itemnumber, src_image => $toc_image })->store; # FIXME handle error
    }

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
                                                # For grouped, should not we actually retrieve the issn/ean from the bib record? ean or isbn? config parameter?
        my $release_code = $cgi->param('release_code');

        $issn_ean = '4190191702107'; $release_code = '2020005'; # FIXME RMME hardcoded

        my $presseplus_info = $self->retrieve_info( $issn_ean, $release_code );

        my $item = $self->build_item({ biblionumber => $biblionumber, table_of_content => $presseplus_info->{contentList} });

        my $image = $self->retrieve_cover_image( $issn_ean, $release_code );
        Koha::CoverImage->new({ itemnumber => $item->itemnumber, src_image => $image })->store; # FIXME handle error

        if ( $self->retrieve_data('toc_image') ) {
            my $toc_image = $self->retrieve_toc_image( $issn_ean, $release_code );
            Koha::CoverImage->new({ itemnumber => $item->itemnumber, src_image => $toc_image })->store; # FIXME handle error
        }

        $template->param(
            biblio => Koha::Biblios->find($biblionumber),
            plugin => $self,
        );
        #print $cgi->redirect("/cgi-bin/koha/catalogue/detail.pl?biblionumber=$biblionumber");
        print $cgi->redirect(sprintf "/cgi-bin/koha/cataloguing/additem.pl?op=edititem&biblionumber=%s&itemnumber=%s#edititem", $item->biblionumber, $item->itemnumber);
        exit;
    }

    $template->param(C4::Search::enabled_staff_search_views);
    $self->output_html( $template->output );
}

sub retrieve_toc_image {
    my ( $self, $issn_ean, $release_code ) = @_;

    my $req = HTTP::Request->new(
        GET => sprintf 'https://service.presseplus.de/content/%s/%s/%s',
        $self->retrieve_data('coversize') || 200, $issn_ean, $release_code
    );
    my $res = LWP::UserAgent->new->request($req);

    #unless ( $res->is_success ) { # FIXME this always return 404
    #    #        use Data::Printer colored => 1; warn p $res;
    #    die "what's happening here?"; # FIXME be nice with the enduser
    #}

    return GD::Image->new( $res->content );    # FIXME handle error
}

sub retrieve_cover_image {
    my ( $self, $issn_ean, $release_code ) = @_;

    my $req = HTTP::Request->new(
        GET => sprintf 'https://cover.presseplus.eu/%s/%s/%s',
        $self->retrieve_data('coversize') || 200, $issn_ean, $release_code
    );
    my $res = LWP::UserAgent->new->request($req);

    unless ( $res->is_success ) {
        use Data::Printer colored => 1; warn p $res;
        die "what's happening here?"; # FIXME be nice with the enduser
    }

    return GD::Image->new( $res->content );    # FIXME handle error
}

sub retrieve_info {
    my ( $self, $issn_ean, $release_code ) = @_;

    my $req = HTTP::Request->new(GET => sprintf 'https://service.presseplus.de/contentText/%s/%s', $issn_ean, $release_code);
    #my apikey = $self->retrieve_data('apikey'); # FIXME do we need that finally?
    #$req->header('ApiKey' => $apikey);
    my $res = LWP::UserAgent->new->request($req);

    unless ( $res->is_success ) {
        use Data::Printer colored => 1; warn p $res;
        die "what's happening here?"; # FIXME be nice with the enduser
    }

    return decode_json( $res->content );
}

sub build_biblio {
    my ( $self, $info ) = @_;

    my $title            = $info->{title};
    my $number           = $info->{number};
    my $description      = $info->{description};
    my $publication_date = $info->{publication_date};
    my $table_of_content = $info->{table_of_content};


    $publication_date =~ s|^(\d{4}-\d{2}-\d{2}).*$|$1|; # FIXME other format needed?

    # 245$a = BRAVO
    #    $n = 2018017
    #    $p = "Größte Jugendzeitschrift"

    my $record = MARC::Record->new;
    C4::Charset::SetMarcUnicodeFlag( $record, C4::Context->preference("marcflavour") );

    $record->append_fields(
        MARC::Field->new(
            '245', '0', '0',
            'a' => $title,
            'n' => $number,
            'p' => $description,
        )
    );
    $record->append_fields(
        MARC::Field->new( '260', '0', '0', 'c' => $publication_date, ) );
    for my $toc (@{$table_of_content}) {
        $record->append_fields(
            MARC::Field->new(
                '505', '0', '',
                # FIXME in a or t?
                #'a' => sprintf ("%s - %s", $toc->{headline}, $toc->{content}),
                't' => sprintf ("%s - %s", $toc->{headline}, $toc->{content}),
            ) );    # FIXME How to display "headline - content"?
    }

    $record->append_fields(
        MARC::Field->new( '942', '0', '0', 'c' => $self->default_itemtype ) );

    my ( $biblionumber ) = C4::Biblio::AddBiblio($record, $self->default_framework);
    return $biblionumber;
}

sub build_item {
    my ( $self, $info ) = @_;

    my $biblionumber = $info->{biblionumber};
    my $table_of_content = $info->{table_of_content} || [];

    my $logged_in_user = Koha::Patrons->find( C4::Context->userenv->{number} );

    return Koha::Item->new(
        {
            biblionumber  => $biblionumber,
            barcode       => undef,                         # FIXME No barcode?
            homebranch    => $logged_in_user->branchcode,
            holdingbranch => $logged_in_user->branchcode,
            itype         => $self->default_itemtype,
            (
                @$table_of_content
                ? (itemnotes => join "\n", map { sprintf "%s - %s", $_->{headline}, $_->{content}} @$table_of_content)
                : ()
            ),

            # FIXME notforloan status? Otherwise it's "available"
        }
    )->store;
}

sub default_itemtype {
    my ($self) = @_;

    return $self->retrieve_data('default_itemtype')
      || Koha::ItemTypes->search->next->itemtype;
}

sub default_framework {
    my ($self) = @_;

    return $self->retrieve_data('default_framework') || '';
}

1;
