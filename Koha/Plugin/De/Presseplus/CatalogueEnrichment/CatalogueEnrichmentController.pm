package Koha::Plugin::De::Presseplus::CatalogueEnrichment::CatalogueEnrichmentController;

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# This program comes with ABSOLUTELY NO WARRANTY;

use Modern::Perl;
use utf8;

use JSON;

use Data::Dumper;

use Mojo::Base 'Mojolicious::Controller';
use Koha::Plugin::De::Presseplus::CatalogueEnrichment;

sub getJournalList {
    my $c = shift->openapi->valid_input or return;

    my $plugin = Koha::Plugin::De::Presseplus::CatalogueEnrichment->new();
    my $search = $c->validation->param('search');

    my $response = $plugin->get_journal_list();
    
    if ( $search ) {
        my @found   = grep {
                         $_->{name} =~ /$search/i || $_->{issn} =~ /$search/i || $_->{ean} =~ /$search/i
                      } @$response;
        $response = \@found;
    }
    
    return $c->render(status  => 200, openapi => $response );
}

1;
