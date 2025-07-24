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
use utf8;

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
use Koha::Serials;
use Koha::Serial::Items;
use Koha::DateUtils qw( dt_from_string output_pref );
use GD::Image;
use LWP::UserAgent;
use HTTP::Request;
use JSON qw( decode_json );
use Try::Tiny;
use Koha::Cache::Memory::Lite;

our $VERSION = "0.1.4";
our $MINIMUM_VERSION = "22.11";

our $metadata = {
    name            => 'Catalogue enrichment plugin for Presseplus',
    author          => 'Jonathan Druart & LMSCloud GmbH',
    date_authored   => '2020-07-23',
    date_updated    => "2021-12-10",
    minimum_version => $MINIMUM_VERSION,
    maximum_version => undef,
    version         => $VERSION,
    description     => 'Plugin zur Anreicherung von Katalog- und/oder Exemplarsätzen für Zeitschriftenhefte von Presseplus',
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
    .chocolat-wrapper.chocolat-visible {
        z-index: 1042;
        opacity: .9;
    }
    #pp-modal {
        z-index: 1041;
    }
    #pp-modal .modal-dialog {
        margin: 10% 20%;
        max-width: none;
    }
    .pp-toc .contents {
        width: 100%;
    }
    .pp-images {
        text-align: center;
    }
    #opac-detail #holdingst .itemnotes {
      width: 8em;
      display: table-cell;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
    #opac-detail #holdingst .bookcover img {
        max-height: 100%;
        max-width: 100%;
        margin: unset;
    }
</style>
    |;
}

sub opac_js {
    my ( $self ) = @_;

    return q?
    <script>
    ? . $self->getBstrapModal() .
    ( $self->retrieve_data('opac_item_cover_view_with_content') ? q|
    if ( $("#opac-detail").size() ) { // We are on the opac-detail page

        let biblio_title = $(".biblio-title").html();
        let pp_modal = $('<div id="pp-modal" class="modal"><div class="modal-dialog" role="document"><div class="modal-content"><div class="modal-header"><h1>' + biblio_title + ' </h1><button type="button" class="closebtn" data-dismiss="modal" aria-label="Close"><span aria-hidden="true">&times;</span></button></div><div class="modal-body"><div class="row"><div class="col-lg-8"><div class="pp-images"></div></div><div class="col-lg-4"><div class="pp-toc"></div></div></div><div class="modal-footer"><div class="pp-show_toc chocolat-image"><a href="" class="chocolat-image fr no-underline blue">Show Table of Contents Image</a></div></div></div></div></div>');
        $(pp_modal).appendTo($('#opac-detail > #wrapper > .main'));

        $("#holdingst .bookcover").each(function(){
            var coverimages_divs = $(this).find('.local-coverimg');
            $(coverimages_divs[0]).find('img').on('click', function(e){
                if ( $(this).parents("tr").find("td.notes").text().length ) {
                    var toc = $(this).parents("tr").find("td.notes").text();
                    $(".pp-toc").empty().append(toc);
                } 
                else if ( $(this).parents("tr").next("tr.child").find("span.dtr-title:contains('Notes')").parent().children("span.dtr-data").length ) {
                    var toc = $(this).parents("tr").next("tr.child").find("span.dtr-title:contains('Notes')").parent().children("span.dtr-data").text();
                    $(".pp-toc").empty().append(toc);
                } 
                else if ( $(this).parents("#catalogue_detail_biblio").length ) {
                    var toc = $("#catalogue_detail_biblio .contents").clone();
                    if ( !toc.length ) {
                        return true;
                    }
                    $(".pp-toc").empty().append(toc);
                }

                e.stopPropagation();
                e.preventDefault();

                var coverimages_divs = $(this).parents('.cover-slider').find('.local-coverimg');

                var main_image_url = $(coverimages_divs[0]).find('a').attr('href');
                var main_image = $("<div>", { class: 'chocolat-image', html: $("<a>", {href: main_image_url, html: $("<img>", {src: main_image_url } ) } ) } );
                $(".pp-images").empty().append(main_image);
                var toc_a = $(coverimages_divs[1]).find('a');
                var show_toc = $(toc_a).clone();
                $(show_toc).text(_("Zeige Inhaltsverzeichnis"));
                $(".pp-show_toc").empty().append($(show_toc).clone());

                Chocolat(document.querySelectorAll('.chocolat-image a'))

                $('#pp-modal').modal('show');
                return false;
            });
        });
    }
    | : '') . q|
    $(document).ready( function(){
        $('#holdingst').dataTable().fnSettings().responsive.c.details.display = $.fn.dataTable.Responsive.display.childRow; 
        $( "#opac-detail #holdingst .notes" ).each(function( index ) {
            var newContent = $('<div/>').addClass('itemnotes').html(this.innerText);
            $(this).empty().append(newContent);
            //if ( this.innerText.length > 0 && this.offsetWidth < this.scrollWidth ) {
            //    var fullText = this.innerText;
            //    $('<a>Mehr</a>').click( function( event ){
            //        new BstrapModal('Inhalt',fullText,'').Show();
            //    }).insertAfter(this);
            //}
        });
    });
    </script>
    |;
}

sub intranet_head {
    my ( $self ) = @_;

    return q|
        <style>
            #catalog_detail #holdings_table .itemnotes {
              overflow: hidden;
              text-overflow: ellipsis;
              white-space: nowrap;
              width: 8em;
            }
        </style>
    |;
}

sub getBstrapModal {
     return q?
        var BstrapModal = function (title, body, buttons) {
            var title = title || "Details", 
                body = body || "Inhalt", 
                buttons = buttons || [{ Value: "Schließen", Css: "btn-primary", Callback: function (event) { BstrapModal.Close(); } }];
                
            BstrapModal.HtmlEncode = function (value,withBreak) {
                console.log($('<div/>').text(value).html());
                var txt = $('<div/>').text(value).html();
                if ( withBreak ) {
                    txt = txt.split('\n').filter(v => v.trim()).map(content => `<p>${content.trim()}</p>`).join('\n');
                }
                return txt;
            };
            var GetModalStructure = function () {
                var that = this;
                that.Id = BstrapModal.Id = Math.random();
                var buttonshtml = "";
                for (var i = 0; i < buttons.length; i++) {
                    buttonshtml += "<button type='button' class='btn " + 
                    (buttons[i].Css||"") + "' name='btn" + that.Id + 
                    "'>" + (buttons[i].Value||"Schließen") + 
                    "</button>";
                }
                return "\
                <div class='modal' name='dynamiccustommodal' id='" + that.Id + "' tabindex='-1' role='dialog' \
                    data-backdrop='static' aria-labelledby='" + that.Id + "Label' aria-hidden='true'>\
                    <div class='modal-dialog'>\
                        <div class='modal-content'>\
                            <div class='modal-header'>\
                                <h4 class='modal-title' style='display:inline'>" + BstrapModal.HtmlEncode(title) + "</h4>\
                                <button type='button' class='closebtn' data-dismiss='modal' aria-label='Close'>\
                                    <span aria-hidden='true'>&times;</span>\
                                </button>\
                            </div>\
                            <div class='modal-body'>\
                                <div class='row'>\
                                    <div class='col-xs-12 col-md-12 col-sm-12 col-lg-12'>" + BstrapModal.HtmlEncode(body,true) + "</div>\
                                </div>\
                            </div>\
                            <div class='modal-footer bg-default'>\
                                <div class='col-xs-12 col-sm-12 col-lg-12'>" + buttonshtml + "</div>\
                            </div>\
                        </div>\
                    </div>\
                </div>";
            }();
            BstrapModal.Delete = function () {
                var modals = document.getElementsByName("dynamiccustommodal");
                if (modals.length > 0) document.body.removeChild(modals[0]);
            };
            BstrapModal.Close = function () {
                $(document.getElementById(BstrapModal.Id)).modal('hide');
                BstrapModal.Delete();
            };
            this.Show = function () {
                BstrapModal.Delete();
                document.body.appendChild($(GetModalStructure)[0]);
                var btns = document.querySelectorAll("button[name='btn" + BstrapModal.Id + "']");
                for (var i = 0; i < btns.length; i++) {
                    btns[i].addEventListener("click", buttons[i].Callback || BstrapModal.Close);
                }
                $(document.getElementById(BstrapModal.Id)).modal('show');
            };
        };?;
}

sub intranet_js {
    my ( $self ) = @_;

    return q|| unless $self->retrieve_data('can_be_grouped');

    my $biblionumber = $self->{cgi}->param('biblionumber');
    
    my $intranetJSadd = q?
    <script>
    ? . $self->getBstrapModal();
    
    if ( $biblionumber ) {
        $intranetJSadd .= sprintf q|
        $('<li><a href="/cgi-bin/koha/plugins/run.pl?class=%s&method=catalogue&biblionumber=%s">Neues Heft von Presseplus</a></li>').insertAfter($("#newitem").parent());
        |, $self->{metadata}->{class}, $biblionumber;
    } else {
        $intranetJSadd .= q|
        $(document).ready( function(){
            $("#cat_cataloging-home h3:contains('Import')").next("ul").prepend('<li><a class="circ-button" href="/cgi-bin/koha/plugins/run.pl?class=Koha%3A%3APlugin%3A%3ADe%3A%3APresseplus%3A%3ACatalogueEnrichment&method=tool"><i class="fa fa-newspaper-o"></i> ZS-Heft als Titel (Presseplus)</a>');
        });
        |;
    }
    
    $intranetJSadd .= q?
        $(document).ready( function(){
            $( "#catalog_detail #holdings_table .itemnotes" ).each(function( index ) {
                if ( this.innerText.length > 0 && this.offsetWidth < this.scrollWidth ) {
                    var fullText = this.innerText;
                    $('<a>Mehr lesen</a>').click( function( event ){
                        new BstrapModal('Inhalt',fullText,'').Show();
                    }).insertAfter(this);
                }
            });
            $( "#catalog_detail #holdings_table tbody tr" ).each(function( index ) {
                var itemnumber = $(this).data("itemnumber");
                var href = '? .
                sprintf q|/cgi-bin/koha/plugins/run.pl?class=%s&method=enrichItem&biblionumber=%s|, $self->{metadata}->{class}, ($biblionumber||'')
                . q?&itemnumber=' + itemnumber;
                $(this).find('td.actions ul').append('<li><a href="' + href + '"><i class="fa fa-book"></i> Anreichern mit Presseplus</a></li>');
            });
        });
    </script>
    ?;
    return $intranetJSadd;
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
    # Don't exit here!
}

sub configure {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};

    unless ( $cgi->param('save') ) {
        my $template = $self->get_template({ file => 'configure.tt' });

        $template->param(
            apikey                            => $self->retrieve_data('apikey'),
            coversize                         => $self->retrieve_data('coversize'),
            can_be_grouped                    => $self->retrieve_data('can_be_grouped'),
            toc_image                         => $self->retrieve_data('toc_image'),
            default_itemtype                  => $self->retrieve_data('default_itemtype'),
            dbs_group                         => $self->retrieve_data('dbs_group'),
            itemtypes                         => scalar Koha::ItemTypes->search_with_localization,
            default_framework                 => $self->retrieve_data('default_framework'),
            frameworks                        => scalar Koha::BiblioFrameworks->search( {}, { order_by => ['frameworktext'] } ),
            attach_cover_to_biblio            => $self->retrieve_data('attach_cover_to_biblio'),
            opac_item_cover_view_with_content => $self->retrieve_data('opac_item_cover_view_with_content'),
        );

        $self->output_html( $template->output() );
        exit;
    }
    $self->store_data(
        {
            apikey                            => scalar $cgi->param('apikey'),
            coversize                         => scalar $cgi->param('coversize'),
            can_be_grouped                    => scalar $cgi->param('can_be_grouped'),
            toc_image                         => scalar $cgi->param('toc_image'),
            default_itemtype                  => scalar $cgi->param('default_itemtype'),
            default_framework                 => scalar $cgi->param('default_framework'),
            attach_cover_to_biblio            => scalar $cgi->param('attach_cover_to_biblio'),
            dbs_group                         => scalar $cgi->param('dbs_group'),
            opac_item_cover_view_with_content => scalar $cgi->param('opac_item_cover_view_with_content'),
        }
    );
    $self->go_home();
    exit;
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

    my $template = $self->get_template({ file => 'catalogue-ungrouped.tt' });

    $self->output_html( $template->output() );
    exit;
}

sub tool_step2 {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};

    my $template = $self->get_template({ file => 'catalogue-ungrouped.tt' });

    $template->param( plugin => $self );

    my $issn_ean = $cgi->param('issn_ean') || ''; # FIXME Should be in the response, is that issn or ean?
    my $release_year = $cgi->param('release_year') || '';
    my $release_issue = $cgi->param('release_issue') || '';
    my $issn = $cgi->param('issn') || '';
    my $ean = $cgi->param('ean') || '';
    
    my $duplicateCheck = ($cgi->param('duplicateCheck') || 'yes');
    if ( $duplicateCheck eq 'yes' ) {
        $duplicateCheck = 1;
    } else {
        $duplicateCheck = 0;
    }
    
    my $release_code = $release_year . $release_issue;
    
    if ( $release_issue && $release_issue =~ /^\d{1,3}$/ ) {
        $release_code = $release_year . sprintf("%03d",$release_issue);
    }

    my ( @messages, @errors );
    my $biblionumber;
    my $duplicateCheckResult;
    try {
        my $presseplus_info = $self->retrieve_info( $issn_ean, $release_code );

        die "Not a valid issn/ean - release code couple\n"
            if $presseplus_info->{description} eq ""
                and $presseplus_info->{name} eq "";

        ($biblionumber,$duplicateCheckResult) = $self->build_biblio(
            {
                title            => $presseplus_info->{name},
                number           => $presseplus_info->{releaseCode},
                description      => $presseplus_info->{description},
                publication_date => $presseplus_info->{evt},
                table_of_content => $presseplus_info->{contentList},
                issn             => $issn,
                ean              => $ean,
                year             => $release_year,
                issue            => $release_issue
            },
            $duplicateCheck
        );

		if ( $biblionumber ) {
			my $item = $self->build_item({biblionumber => $biblionumber});

			push @messages, {
				code => 'success_on_retrieve_info',
			};
		}
		else {
			if ( $duplicateCheckResult ) {
                my @duplicateList = $duplicateCheckResult->as_list;
				push @errors, {
					code => 'duplicate_found',
					data => \@duplicateList
				};
			}
			
			$template->param(
				errors => \@errors,
				messages => \@messages,
				issn_ean => $cgi->param('issn_ean'),
				release_year => $cgi->param('release_year'),
				release_issue => $cgi->param('release_issue'),
				issn => $cgi->param('issn'),
                title => $cgi->param('title'),
				ean => $cgi->param('ean')
			);
		}
    } catch {
        push @errors, {
            code => 'error_on_retrieve_info',
            error => $_,
        };

        $template->param(errors => \@errors);

        $self->output_html( $template->output );
        exit;
    };

    try {
        my $image = $self->retrieve_cover_image( $issn_ean, $release_code );
        if ( $image ) {
            Koha::CoverImage->new(
                {
                    biblionumber => $biblionumber,
                    src_image => $image,
                    dont_scale => 1
                }
            )->store;
            push @messages, {
                code => 'success_on_retrieve_image',
            };
        } else {
            push @messages, {
                code => 'no_cover_image',
            };
        }
    } catch {
        push @errors, {
            code => 'error_on_retrieve_image',
            error => $_,
        };
    };

    if ( $self->retrieve_data('toc_image') ) {
        try {
            my $toc_image = $self->retrieve_toc_image( $issn_ean, $release_code );
            if ( $toc_image ) {
                Koha::CoverImage->new({ biblionumber => $biblionumber, src_image => $toc_image, dont_scale => 1 })->store;
                push @messages, {
                    code => 'success_on_retrieve_toc_image',
                };
            } else {
                push @messages, {
                    code => 'no_toc_image',
                };
            }
        } catch {
            push @errors, {
                code => 'error_on_retrieve_toc_image',
                error => $_,
            };
        };
    }

    $template->param(
        errors => \@errors,
        messages => \@messages,
        new_biblio => Koha::Biblios->find($biblionumber),
    );

    $self->output_html( $template->output() );
    exit;
}

sub enrichItem {
    my ($self, $args) = @_;

    my $cgi = $self->{cgi};
    my $template = $self->get_template({
        file => 'catalogue.tt'
    });
    my @errors;
    my @messages;
    
    # The biblio we're working with
    my $biblionumber = $cgi->param('biblionumber');
    my $biblio       = Koha::Biblios->find( $biblionumber );
    my $biblioitem   = Koha::Biblioitems->find( { biblionumber => $biblionumber } );
    die "no biblio for biblionumber=$biblionumber" unless $biblio; # FIXME handle that gracefully
    
    my $itemnumber   = $cgi->param('itemnumber');
    my $item         = Koha::Items->find($itemnumber);
    die "no item for itemnumber=$itemnumber" unless $item; # FIXME handle that gracefully
    
    my $serial_item  = Koha::Serial::Items->find( { itemnumber => $itemnumber } );
    my $serial;
    if ( $serial_item ) {
        $serial = Koha::Serials->find($serial_item->serialid);
    }
    # try to identify the year and the issuenumber
    my $issueyear = $self->{cgi}->param('release_year');
    my $issuenumber = $self->{cgi}->param('release_issue');
    
    if ( !$issueyear || !$issuenumber || ($issueyear && $issueyear !~ /^2[0-9]{3}$/) || ($issuenumber && $issuenumber !~ /^[0-9]{1,3}$/) ) {
        my $enumchron = $item->enumchron;
        my $dateaccessioned = $item->dateaccessioned;

        $enumchron =~ s/[012]?[0-9]\.[01]?[0-9]\.20[0-9]{2}//;
        
        # Next, if not found, try to find a four digit year in the enumchron value of the item
        if ( !$issueyear && $enumchron =~ /(20[0-9]{2})/ ) {
            $issueyear = $1;
            $enumchron =~ s/20[0-9]{2}//;
        }
        # If not found, use a possible availabe accession date
        if ( !$issueyear && $dateaccessioned =~ /^([0-9]{4})/  ) {
            $issueyear = $1;
        }
        
        # First try to get the year from a serial item if available
        if ( !$issueyear && $serial ) {
            if ( $serial->publisheddate && $serial->publisheddate =~ /^([0-9]{4})/ ) {
                $issueyear = $1;
            }
            if ( !$issueyear && $serial->planneddate && $serial->planneddate =~ /^([0-9]{4})/ ) {
                $issueyear = $1;
            }
        }
        
        # If not found, try to find a two digit year in the enumchron value
        if ( !$issueyear && $enumchron =~  /([123456][0-9])/ ) {
            $issueyear = $1;
            $enumchron =~ s/[123456][0-9]//;
        }
        
        # Now try to parse the issuenumber
        if ( !$issuenumber && $enumchron =~  /([0-9]+)/ ) {
            $issuenumber = $1 + 0;
            $issuenumber = sprintf("%03d",$issuenumber);
        }
    }
    
    $template->param(
        plugin => $self,
        biblio => $biblio,
        biblioitem => $biblioitem,
        item => $item,
        issueyear => $issueyear,
        issuenumber => $issuenumber,
        apikey => $self->retrieve_data('apikey'),
        enrichItem => 1,
        C4::Search::enabled_staff_search_views,
    );

    if ( $issueyear && $issuenumber && $issueyear =~ /^2[0-9]{3}$/ && $issuenumber =~ /^[0-9]{1,3}$/ ) {
        my $ean = $self->{cgi}->param('ean');
        $ean = $biblioitem->ean if (!$ean);
        my $issn = $self->{cgi}->param('issn');
        $issn = $biblioitem->issn if (!$issn);
        
        my $release_code = $issueyear . $issuenumber;
        
        if ( $issueyear && $issuenumber =~ /^\d{1,3}$/ ) {
            $release_code = $issueyear . sprintf("%03d",$issuenumber);
        }

        my $presseplus_info;
        my $issn_ean;
        
       try {
            if ( $ean ) {
                $presseplus_info = $self->retrieve_info( $ean, $release_code );
                $issn_ean = $ean;
            }
            if ( $issn && (!$presseplus_info || ($presseplus_info->{description} eq "" and $presseplus_info->{name} eq "" ) ) ) {
                $presseplus_info = $self->retrieve_info( $issn, $release_code );
                $issn_ean = $issn;
            }
            die "Keine gültige IISSN/EAN oder Heftnummer für die Presseplus-Abfrage. Die Angaben konnten bei Presseplus nicht ermitteln werden.\n"
                if $presseplus_info->{description} eq "" and $presseplus_info->{name} eq "";

            push @messages, {
                code => 'success_on_retrieve_info',
            };
        } catch {
            push @errors, {
                code => 'error_on_retrieve_info',
                error => $_,
            };
        };
        
        
        if ( !$presseplus_info || ($presseplus_info->{description} eq "" and $presseplus_info->{name} eq "") ) {
            push @errors, {
                code => 'error_on_retrieve_info',
                error => "Keine gültige ISSN/EAN oder Heftnummer für die Presseplus-Abfrage. Die Angaben konnten bei Presseplus nicht ermitteln werden.\n",
            };

            $template->param(errors => \@errors);
        } else {

            my $logged_in_user = Koha::Patrons->find( C4::Context->userenv->{number} );
            
            my $upd_issuenumber;
            if ( $issuenumber && $issueyear ) {
                $upd_issuenumber = $issuenumber . '/' . $issueyear;
                if ( $issuenumber =~ /^\d{1,3}$/ ) {
                    $upd_issuenumber = sprintf("%d",$issuenumber) . '/' . $issueyear;
                }
            }
            
            my $table_of_content = $presseplus_info->{contentList};
            my $itemnotes;
            if ( $table_of_content && scalar(@$table_of_content) ) {
                $itemnotes = join "\n", map { sprintf "%s - %s", $_->{headline}, $_->{content}} @$table_of_content;
            }
                
            my $changed = 0;
            if ( !($item->homebranch) ) {
                $item->homebranch($logged_in_user->branchcode);
                $changed++;
            }
            if ( !($item->holdingbranch) ) {
                $item->holdingbranch($logged_in_user->branchcode);
                $changed++;
            }
            if ( !($item->itype) && $self->default_itemtype) {
                $item->itype($self->default_itemtype);
                $changed++;
            }
            if ( !($item->coded_location_qualifier) && $self->default_dbs_group ) {
                $item->coded_location_qualifier($self->default_dbs_group);
                $changed++;
            }
            if ( !($item->enumchron) ) {
                $item->enumchron($upd_issuenumber);
                $changed++;
            }
            if ( $itemnotes ) {
                $item->itemnotes($itemnotes);
                $changed++;
            }
            $item->store if ($changed);
            
            my $coverImages = $item->cover_images;
            $coverImages->delete if ( $coverImages );
                    
            try {
                my $image = $self->retrieve_cover_image( $issn_ean, $release_code );
                if ( $image ) {
                    Koha::CoverImage->new(
                        {
                            itemnumber => $item->itemnumber,
                            src_image => $image,
                            dont_scale => 1
                        }
                    )->store;
                    push @messages, {
                        code => 'success_on_retrieve_image',
                    };
                } else {
                    push @messages, {
                        code => 'no_cover_image',
                    };
                }
            } catch {
                push @errors, {
                    code => 'error_on_retrieve_image',
                    error => $_,
                };
            };
            
            if ( $self->retrieve_data('toc_image') ) {
                try {
                    my $toc_image = $self->retrieve_toc_image( $issn_ean, $release_code );
                    if ( $toc_image ) {
                        Koha::CoverImage->new(
                            { 
                                    itemnumber => $item->itemnumber, 
                                    src_image => $toc_image, 
                                    dont_scale => 1 
                            }
                        )->store;
                        push @messages, {
                            code => 'success_on_retrieve_toc_image',
                        };
                    } else {
                        push @messages, {
                            code => 'no_toc_image',
                        };
                    }
                } catch {
                    push @errors, {
                        code => 'error_on_retrieve_toc_image',
                        error => $_,
                    };
                };
            }

            $template->param(
                error => \@errors,
                messages => \@messages,
                updated_item => $item,
            );
        }
    }

    $self->output_html( $template->output );
    exit;
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
    my $biblioitem = Koha::Biblioitems->find( { biblionumber => $biblionumber } );
    die "no biblio for biblionumber=$biblionumber" unless $biblio; # FIXME handle that gracefully

    $template->param(
        plugin => $self,
        biblio => $biblio,
        biblioitem => $biblioitem,
        apikey => $self->retrieve_data('apikey'),
        C4::Search::enabled_staff_search_views,
    );

    my ( @messages, @errors );
    if ( $cgi->param('submitted') ) {

        my $issn_ean = $cgi->param('issn_ean'); 
        my $release_year = $cgi->param('release_year') || '';
        my $release_issue = $cgi->param('release_issue') || '';
        my $issn = $cgi->param('issn') || '';
        my $ean = $cgi->param('ean') || '';
        
        my $issuenumber;
        if ( $release_issue && $release_year ) {
            $issuenumber = $release_issue . '/' . $release_year;
            if ( $release_issue =~ /^\d{1,3}$/ ) {
                $issuenumber = sprintf("%d",$release_issue) . '/' . $release_year;
            }
        }
        
        my $release_code = $release_year . $release_issue;
        
        if ( $release_issue && $release_issue =~ /^\d{1,3}$/ ) {
            $release_code = $release_year . sprintf("%03d",$release_issue);
        }

        my $item;
        try {
            my $presseplus_info = $self->retrieve_info( $issn_ean, $release_code );

            die "Keine gültige ISSN/EAN - Release Code Kombination für Presseplus. Die Angaben konnten bei Presseplus nicht ermitteln werden.\n"
                if $presseplus_info->{description} eq ""
                    and $presseplus_info->{name} eq "";

            $item = $self->build_item({ biblionumber => $biblionumber, 
                                        table_of_content => $presseplus_info->{contentList},
                                        issuenumber => $issuenumber
                                      });
            push @messages, {
                code => 'success_on_retrieve_info',
            };
        } catch {
            push @errors, {
                code => 'error_on_retrieve_info',
                error => $_,
            };

            $template->param(errors => \@errors);

            $self->output_html( $template->output );
            exit;
        };

        try {
            my $image = $self->retrieve_cover_image( $issn_ean, $release_code );
            if ( $image ) {
                Koha::CoverImage->new(
                    {
                        itemnumber => $item->itemnumber,
                        (
                            $self->retrieve_data('attach_cover_to_biblio')
                            ? ( biblionumber => $item->biblionumber )
                            : ()
                        ),
                        src_image => $image,
                        dont_scale => 1
                    }
                )->store;
                push @messages, {
                    code => 'success_on_retrieve_image',
                };
            } else {
                push @messages, {
                    code => 'no_cover_image',
                };
            }
        } catch {
            push @errors, {
                code => 'error_on_retrieve_image',
                error => $_,
            };
        };

        if ( $self->retrieve_data('toc_image') ) {
            try {
                my $toc_image = $self->retrieve_toc_image( $issn_ean, $release_code );
                if ( $toc_image ) {
                    Koha::CoverImage->new({ itemnumber => $item->itemnumber, src_image => $toc_image, dont_scale => 1 })->store;
                    push @messages, {
                        code => 'success_on_retrieve_toc_image',
                    };
                } else {
                    push @messages, {
                        code => 'no_toc_image',
                    };
                }
            } catch {
                push @errors, {
                    code => 'error_on_retrieve_toc_image',
                    error => $_,
                };
            };
        }

        $template->param(
            error => \@errors,
            messages => \@messages,
            new_item => $item,
        );
    }

    $self->output_html( $template->output );
    exit;
}

sub retrieve_toc_image {
    my ( $self, $issn_ean, $release_code ) = @_;

    my $req;
    my $apikey = $self->retrieve_data('apikey'); 
    if ( $apikey ) {
        $req = HTTP::Request->new(
            GET => sprintf 'https://contents.presseplus.eu/%s/%s/%s?Auth=%s',
            $self->retrieve_data('coversize') || 'original', $issn_ean, $release_code, $apikey
        );
    } else {
        $req = HTTP::Request->new(
            GET => sprintf 'https://contents.presseplus.eu/%s/%s/%s',
            $self->retrieve_data('coversize') || 'original', $issn_ean, $release_code
        );
    }
    my $res = LWP::UserAgent->new->request($req);

    return if $res->code == 404;

    unless ( $res->is_success ) {
        die sprintf "Cannot retrieve toc image: %s (%s)", $res->msg, $res->code;
    }

    return GD::Image->new( $res->content );
}

sub retrieve_cover_image {
    my ( $self, $issn_ean, $release_code ) = @_;

    my $req;
    my $apikey = $self->retrieve_data('apikey'); 
    if ( $apikey ) {
        $req = HTTP::Request->new(
            GET => sprintf 'https://cover.presseplus.eu/%s/%s/%s?Auth=%s',
            $self->retrieve_data('coversize') || 'original', $issn_ean, $release_code, $apikey
        );
    } else {
        $req = HTTP::Request->new(
            GET => sprintf 'https://cover.presseplus.eu/%s/%s/%s',
            $self->retrieve_data('coversize') || 'original', $issn_ean, $release_code
        );
    }

    my $res = LWP::UserAgent->new->request($req);

    return if $res->code == 404;

    unless ( $res->is_success ) {
        die sprintf "Cannot retrieve cover image: %s (%s)", $res->msg, $res->code;
    }

    return GD::Image->new( $res->content );
}

sub retrieve_info {
    my ( $self, $issn_ean, $release_code ) = @_;

    my $req;
    my $apikey = $self->retrieve_data('apikey'); 
    if ( $apikey ) {
        $req = HTTP::Request->new(GET => sprintf 'https://service.presseplus.de/contentText/%s/%s?Auth=%s', $issn_ean, $release_code, $apikey);
    } else {
        $req = HTTP::Request->new(GET => sprintf 'https://service.presseplus.de/contentText/%s/%s', $issn_ean, $release_code);
    }
    
    my $res = LWP::UserAgent->new->request($req);

    unless ( $res->is_success ) {
        die sprintf "Cannot retrieve info: %s (%s)", $res->msg, $res->code;
    }

    return decode_json( $res->content );
}

sub get_journal_list {
    my ( $self, $issn_ean, $release_code ) = @_;
    my $req;
    my $apikey = $self->retrieve_data('apikey'); 
    my $journalList = [];
    
    if ( $apikey ) {
        
        my $cache     = Koha::Cache::Memory::Lite->get_instance();
        my $cache_key = 'plugin:presseplus:lsttime';

        my $time = $cache->get($cache_key);
        if ($time && (time - $time) < 3600 ) {
            $cache_key = 'plugin:presseplus:journals';
            $journalList = $cache->get($cache_key);
            return ($journalList);
        }
    
        my $nextPortion = 1;
        my $portionSize = 50;
        
        while ( $nextPortion ) {
            $req = HTTP::Request->new(GET => sprintf('https://service.presseplus.de/api/OnlineCatalog/List/%s/productName/asc/%d/%d', $apikey, $nextPortion, $portionSize));
            my $res = LWP::UserAgent->new->request($req);
            
            my $continue = 0;
            if ( $res->is_success ) { 
                my $journals = decode_json( $res->content );
                if ( scalar(@$journals) > 0 ) {
                    foreach my $journal(@$journals) {
                        my $journalAdd = {
                                             name            => $journal->{productName},
                                             issn            => $journal->{issn},
                                             ean             => $journal->{ean},
                                             nextReleaseCode => $journal->{releaseCode},
                                             nextReleaseDate => '',
                                             nextRelease     => $journal->{release},
                                         };
                        if ( $journal->{evt} ) {
                            my $dt = dt_from_string($journal->{evt},'iso');
                            $journalAdd->{nextReleaseDate} = output_pref( { dt => $dt, dateonly => 1 } );
                        }
                        if ( $journal->{release} =~ /^([^\/]+)\/([^\/]{4})$/ ) {
                            $journalAdd->{nextReleaseYear} = $2;
                            $journalAdd->{nextReleaseIssue} = $1;
                        }
                        
                        push(@$journalList,$journalAdd);
                    }
                    $nextPortion++;
                    $continue++;
                }
            }
            
            $nextPortion = 0 if ( $nextPortion > 100 || !$continue);
        }
        
        if ( scalar(@$journalList) > 0 ) {
            $cache->set( $cache_key, time );
            $cache_key = 'plugin:presseplus:journals';
            $cache->set( $cache_key, $journalList );
        }
    }
    
    return $journalList;
}

sub build_biblio {
    my ( $self, $info, $doDuplicateCheck ) = @_;

    my $title            = $info->{title};
    my $number           = $info->{number};
    my $description      = $info->{description};
    my $publication_date = $info->{publication_date};
    my $table_of_content = $info->{table_of_content};
    my $issn             = $info->{issn};
    my $ean              = $info->{ean};
    my $year             = $info->{year};
    my $issue            = $info->{issue};

    if ( $issue && $year ) {
        $number = $issue . '/' . $year;
        if ( $issue =~ /^\d{1,3}$/ ) {
            $number = sprintf("%d",$issue) . '/' . $year;
        }
    }

    $publication_date =~ s|^(\d{4}-\d{2}-\d{2}).*$|$1|; # FIXME other format needed?

    # 245$a = BRAVO
    #    $n = 2018017
    #    $p = "Größte Jugendzeitschrift"

    my $record = MARC::Record->new;
    C4::Charset::SetMarcUnicodeFlag( $record, C4::Context->preference("marcflavour") );

    if ( $issn ) {
        $record->append_fields(
            MARC::Field->new('022', ' ', ' ', 'a' => $issn)
        );
    }
    if ( $ean ) {
        $record->append_fields(
            MARC::Field->new('024', '3', ' ', 'a' => $ean)
        );
    }
    
    my $searchValues = {};
    my @fieldValues;
    
    if ( $title ) {
		$searchValues->{title} = $title;
		push @fieldValues, 'a' => $title;
	}
	if ( $number ) {
		$searchValues->{part_number} = $number;
		push @fieldValues, 'n' => $number;
	}
	if ( $description ) {
		$searchValues->{part_name} = $description;
		push @fieldValues, 'p' => $description;
	}

    $record->append_fields(
        MARC::Field->new(
            '245', '0', '0', @fieldValues
        )
    );
    
    if ( $publication_date && $publication_date =~ /^\d{4}-\d{2}-\d{2}$/ ) {
        eval {
            my $pubdate = output_pref({ str => $publication_date, dateonly => 1 });
            $record->append_fields( MARC::Field->new( '260', '0', '0', 'c' => $pubdate ) );
        };
    }
    
    
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

	if ( $doDuplicateCheck ) {
		my $duplicateCheckResult = Koha::Biblios->search( $searchValues );
		
		if ( $duplicateCheckResult->count ) {
			return (undef,$duplicateCheckResult);
		}
	}
    my ( $biblionumber ) = C4::Biblio::AddBiblio($record, $self->default_framework);
    return ($biblionumber, undef);
}

sub build_item {
    my ( $self, $info ) = @_;

    my $biblionumber = $info->{biblionumber};
    my $table_of_content = $info->{table_of_content} || [];
    my $issuenumber = $info->{issuenumber} || '';

    my $logged_in_user = Koha::Patrons->find( C4::Context->userenv->{number} );

    return Koha::Item->new(
        {
            biblionumber             => $biblionumber,
            barcode                  => undef,                         # FIXME No barcode?
            homebranch               => $logged_in_user->branchcode,
            holdingbranch            => $logged_in_user->branchcode,
            itype                    => $self->default_itemtype,
            coded_location_qualifier => $self->default_dbs_group,
            (
                @$table_of_content
                ? (itemnotes => join "\n", map { sprintf "%s - %s", $_->{headline}, $_->{content}} @$table_of_content)
                : ()
            ),
            (
                $issuenumber ? (enumchron => $issuenumber): ()
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

sub default_dbs_group {
    my ($self) = @_;

    return $self->retrieve_data('dbs_group')
      || 'F_B_P';
}

sub default_framework {
    my ($self) = @_;

    return $self->retrieve_data('default_framework') || '';
}

sub api_routes {
    my ( $self, $args ) = @_;

    my $spec_dir = $self->mbf_dir();

    my $schema = JSON::Validator::Schema::OpenAPIv2->new;
    my $spec = $schema->resolve($spec_dir . '/openapi.yaml');

    return $self->_convert_refs_to_absolute($spec->data->{'paths'}, 'file://' . $spec_dir . '/');
}

sub static_routes {
    my ( $self, $args ) = @_;

    my $spec_str = $self->mbf_read('staticapi.json');
    my $spec     = decode_json($spec_str);

    return $spec;
}


sub api_namespace {
    my ($self) = @_;

    return 'presseplus';
}

sub _convert_refs_to_absolute {
    my ( $self, $hashref, $path_prefix ) = @_;

    foreach my $key (keys %{ $hashref }) {
        if ($key eq '$ref') {
            if ($hashref->{$key} =~ /^(\.\/)?openapi/) {
                $hashref->{$key} = $path_prefix . $hashref->{$key};
            }
        } elsif (ref $hashref->{$key} eq 'HASH' ) {
            $hashref->{$key} = $self->_convert_refs_to_absolute($hashref->{$key}, $path_prefix);
        } elsif (ref($hashref->{$key}) eq 'ARRAY') {
            $hashref->{$key} = $self->_convert_array_refs_to_absolute($hashref->{$key}, $path_prefix);
        }
    }
    return $hashref;
}

sub _convert_array_refs_to_absolute {
    my ( $self, $arrayref, $path_prefix ) = @_;

    my @res;
    foreach my $item (@{ $arrayref }) {
        if (ref($item) eq 'HASH') {
            $item = $self->_convert_refs_to_absolute($item, $path_prefix);
        } elsif (ref($item) eq 'ARRAY') {
            $item = $self->_convert_array_refs_to_absolute($item, $path_prefix);
        }
        push @res, $item;
    }
    return \@res;
}


1;
