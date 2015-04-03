# OopRailsServer

Rails makes it easy enough to write test code or RSpec that runs _within_ Rails. However, what’s much, much harder
is testing code (like a RubyGem) that augments Rails itself, particularly if you want that code to be compatible
with multiple versions of Rails. Often people will simply check in a full Rails tree (_i.e._, that which is generated
by `rails new`), but that fixes you to an exact version of Rails and is difficult to upgrade or manipulate.

`OopRailsServer` provides a completely different, much cleaner solution: it provides an object,
`OopRailsServer::RailsServer`. This object knows how to:

* Install any version of Rails from scratch, completely cleanly (_i.e._, the equivalent of `gem install rails -v=4.2.0`);
* Use that version of Rails to create a new Rails installation (_i.e._, `rails _4.2.0_ new`);
* Add any lines you want to the resulting Rails Gemfile, and run `bundle install` (so that any gems you want —
  for example, the gem you’re testing — are available to that Rails installation);
* Populate that installation by using one or more "template directories" that you provide — each template directory
  is laid out exactly like a standard Rails tree (but need contain only files you actually want to provide), and will
  overwrite the corresponding files in the Rails tree
* Spin up a new Rails server, running on a randomly-assigned port, in that Rails installation;
* Fetch arbitrary URLs from that Rails server on your command;
* When it’s all done, safely (and reliably) terminate that server.

As of this writing, this gem is not fully productized: while it works reliably, there is insufficient documentation
to easily use it yourself. It is, however, very reliable: it is used as the backbone of the test suites for
[`fortitude`](https://github.com/ageweke/fortitude), [`parcels`](https://github.com/ageweke/parcels), and the
backbone of the real work in [`rails_view_benchmarks`](https://github.com/ageweke/rails_view_benchmarks).

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'oop_rails_server'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install oop_rails_server

## Usage

TODO: Write usage instructions here

## Contributing

1. Fork it ( https://github.com/[my-github-username]/oop_rails_server/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
