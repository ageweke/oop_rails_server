# `oop_rails_server` Releases

## 0.0.9,

* Fix issue with Ruby 1.8.x caused by trying to reference RUBY_ENGINE, which isn't defined in 1.8.x.

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
