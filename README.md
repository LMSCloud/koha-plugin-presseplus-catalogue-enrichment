# Koha plugin - catalogue enrichment for Presseplus

This plugin adds the ability to create and enrich catalogue and item records in Koha for magazine issues, using the [Presseplus](https://www.presseplus.de) web services.

## Introduction

Presseplus.de is a web portal in German-speaking countries (Germany, Austria, Switzerland) for the sale of magazine subscriptions to end users. A registered customer can choose from a range of over 1,800 magazines and take out subscriptions or purchase individual issues.

This plugin uses Presseplus's web services to look up a magazine issue by ISSN/EAN and release code, and to pull in metadata (title, description, table of contents, publication date) as well as cover images and table-of-contents images, so that new issues can be catalogued in Koha with minimal manual data entry.

## Features

- **List Pressplus subscriptions** to create bibliographic or item records for serial issues.
- **Look up an issue by ISSN/EAN and release code** against the Presseplus `contentText` web service, retrieving title, issue number, description, publication date, ISSN, and table of contents.
- **Create a new bibliographic record and item** from the retrieved data, or **add an item to an existing bibliographic record** ("enrich" workflow) when the magazine is already catalogued.
- **Download and attach cover images and table-of-contents images** from Presseplus's cover image service, in a configurable size.
- **Toolbar button on the bibliographic detail page** in the staff interface (when enabled) that lets staff jump directly into the enrichment workflow for that record, to add a newly arrived issue.
- **OPAC display enhancement**: when enabled, clicking an item's local cover image on the OPAC detail page opens a modal showing the issue's table of contents alongside the cover.
- **Multiple API keys**: the Presseplus API key setting accepts a `|`-separated list of keys; the plugin picks a key from the list for each request (useful for spreading load across several Presseplus accounts/keys).
- **Response caching**: journal/issue lookups are cached in memory for up to one hour to reduce repeated calls to the Presseplus web service.
- **Configurable cataloguing defaults**: default item type, default MARC framework (with an option to only copy field defaults from that framework rather than switching the whole record to it), and a default shelving/location qualifier ("DBS" classification group) applied to newly created items.
- **REST API endpoint** (namespace `presseplus`) used by the plugin's own staff-interface and OPAC scripts.

## Requirements

- Koha 22.11 or later.
- Perl modules used by the plugin (`GD::Image`, `LWP::UserAgent`, `JSON`, `Try::Tiny`) are part of a standard Koha installation and normally require no separate setup.
- A valid Presseplus API key (or several, `|`-separated) for the library's Presseplus account, entered in the plugin configuration.

## Installation

The Koha plugin system must be enabled by a system administrator before any plugin can be installed:

- Change `<enable_plugins>0</enable_plugins>` to `<enable_plugins>1</enable_plugins>` in your `koha-conf.xml` file.
- Confirm that the path to `<pluginsdir>` exists, is correct, and is writable by the web server.
- Restart your webserver.

Once enabled, download the relevant `*.kpz` package for a release and install it via *Administration → Manage plugins* in the Koha staff interface.

## Configuration

From the plugin's configuration page, you can set:

- **API key(s)**: one or more Presseplus API keys (`|`-separated).
- **Cover image size**: the size requested from the Presseplus cover image service.
- **Grouping / toolbar button**: whether the "enrich this record" toolbar button is shown on the bibliographic detail page.
- **Table-of-contents image**: whether to fetch a separate TOC image in addition to the cover image.
- **OPAC cover + content view**: whether clicking an item's cover on the OPAC detail page opens a modal with the table of contents.
- **Default item type** and **default MARC framework** for newly created records (with an option to only copy that framework's field defaults instead of using it as the record's framework).
- **Default DBS/shelving location qualifier** applied to new items.

## Usage

1. Open a record (or start from scratch) in the staff interface and use the plugin's tool to look up an issue by ISSN/EAN and release code.
2. Review the metadata, cover image, and table of contents retrieved from Presseplus.
3. Either create a new bibliographic record and item, or, using the toolbar button on an existing serial's detail page, add the new issue as an item to that record.
4. If enabled, patrons browsing the OPAC can click an item's cover image to see the table of contents for that issue.

## About Koha plugins

Koha's Plugin System (available in Koha 3.12+) allows you to add additional tools and reports to [Koha](http://koha-community.org) that are specific to your library. Plugins are installed by uploading KPZ (Koha Plugin Zip) packages. A KPZ file is a zip file containing the Perl files, template files, and any other files necessary to make the plugin work. Learn more about the Koha Plugin System in the [Koha manual](https://koha-community.org/manual/).

## License

GPL-3.0, see [LICENSE](LICENSE).
