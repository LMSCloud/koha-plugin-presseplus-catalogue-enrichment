# Koha plugin - catalogue enrichment for Presseplus

This plugin adds the ability to create new entries in Koha catalogues from Presseplus webservices.

## Introduction

Presseplus.de is a web portal in German-speaking countries (Germany, Austria, Switzerland) for sale of magazine subscriptions to end users.

A registered customer can choose from a range of over 1,800 magazines and take out subscriptions or purchase individual issues.

This plugin is designed to create catalogue entries into Koha using Presseplus webervices

It downloads information like the name, description, table of content, as well as cover images of the serial number and its table of content

## Downloading

From the [release page](https://gitlab.com/Joubu/koha-plugin-presseplus-catalogue-enrichment/-/releases) you can download the relevant *.kpz file

## Installing

The plugin system needs to be turned on by a system administrator.

To set up the Koha plugin system you must first make some changes to your install.

* Change `<enable_plugins>0<enable_plugins>` to `<enable_plugins>1</enable_plugins>` in your koha-conf.xml file
* Confirm that the path to `<pluginsdir>` exists, is correct, and is writable by the web server
* Restart your webserver

On the Tools page you will see the Tools Plugins and on the Reports page you will see the Reports Plugins.

## About Koha plugins

Koha’s Plugin System (available in Koha 3.12+) allows for you to add additional tools and reports to [Koha](http://koha-community.org) that are specific to your library. Plugins are installed by uploading KPZ ( Koha Plugin Zip ) packages. A KPZ file is just a zip file containing the perl files, template files, and any other files necessary to make the plugin work. Learn more about the Koha Plugin System in the [Koha 3.22 Manual](http://manual.koha-community.org/3.22/en/pluginsystem.html) or watch [Kyle’s tutorial video](http://bywatersolutions.com/2013/01/23/koha-plugin-system-coming-soon/).

## License

See the LICENSE file
