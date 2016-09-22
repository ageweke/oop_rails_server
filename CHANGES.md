# `oop_rails_server` Releases

## 0.0.20, 22 September 2016

* If exceptions have a `cause`, nest that inside the JSON returned on error.
* Pass 'Accept: text/html' by default when fetching from a Rails server, unless specified otherwise.

## 0.0.19, 20 September 2016

* Significant internal refactor to how Gemfiles get modified that's much more reliable; changes
  `:additional_gemfile_lines` into `:gemfile_modifier`, and from an array of `String`s to a `Proc`.

## 0.0.18, 20 September 2016

* Replicate the workaround for `mime-types` into not just the Rails bootstrap Gemfile, but the Rails gemfile, too.

## 0.0.17, 19 September 2016

* Add workaround for the fact that `mime-types` 3.x depends on `mime-types-data`, which is incompatible with
  Ruby 1.x.

## 0.0.16, 19 September 2016

* Add workarounds for newer versions of `rake` and `uglifier` that cause problems with Ruby 1.8.7.

## 0.0.15, 10 February 2016

* Fix a small regular-expression issue preventing `oop_rails_server` from working on a Rails version that had four
  digits in it (such as the recently-released 4.2.5.1).

## 0.0.14, 6 October 2015

* More tweaks to the conditions under which we lock `rack-cache` to an earlier version.

## 0.0.13, 6 October 2015

* A significantly longer timeout (30 seconds, rather than 15) for starting up the Rails server; some versions of JRuby
  in some environments seem to require this.
* Much better error messages when the server fails to start up, or fails verification.
* Added a workaround for the fact that Rails 3.1.x requires `rack-cache`, but a new version (1.3.0) was just released
  that's incompatible with Ruby < 2.x. We now pin `rack-cache` to `< 1.3.0` when using Rails 3.1.x.

## 0.0.12, 4 October 2015

* Much better error output if the Rails server fails to start up, and willingness to keep trying if it returns an
  error 500 instead of 200 -- occasionally this can happen immediately after startup, on some platforms.

## 0.0.11, 4 October 2015

* Bump up the timeout we use for verifying that the server has started up properly. Travis CI with JRuby sometimes
  seems to take longer than this.

## 0.0.10, 4 October 2015

* Further tweaks to the regexp we use to detect "need remote access" error -- it seems as if JRuby sometimes
  emits this with a newline in the middle.

## 0.0.9, 4 October 2015

* Fix issue with Ruby 1.8.x caused by trying to reference RUBY_ENGINE, which isn't defined in 1.8.x.
* Tweak regexp we use to detect "need remote access" error on "bundle install --local", since it apparently
  changed with a recent release of Bundler.

## 0.0.8, 3 April 2015

* Much better error reporting if the server fails to start up.
* Add `OopRailsServer::RailsServer#setup!`, which configures everything properly but does not actually start
  the out-of-process Rails server yet.
* Allow passing paths or full URIs into `OopRailsServer::RailsServer#get`, as well as passing a separate Hash
  of query values.
* Move question of which templates to use out of `OopRailsServer::Helpers` and into `OopRailsServer::RailsServer`.
* Save away the actual exact versions of Rails and Ruby being used, as well as the `RUBY_ENGINE`, and allow callers
  to access them easily.

## 0.0.7, 21 January 2015

* Further fixes for the `i18n` gem version `0.7.0`.

## 0.0.6, 21 January 2015

* Fix to compensate for the `i18n` gem, which released a version `0.7.0` that is incompatible with
  Ruby 1.8.7.

## 0.0.5, 14 December 2014

* Added `json` as a dependency, since, under Ruby 1.8.7, it is not necessarily installed otherwise.
* `stderr` is now captured to the output file of the Rails server, as well as `stdout`.

## 0.0.4, 13 December 2014

* Better error messages in certain circumstances.
* Expose a `#run_command_in_rails_root!` method to allow executing arbitrary Rails-related commands in the
  server's root.
